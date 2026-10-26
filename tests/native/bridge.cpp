// Native tests for the browser panel's side in MT5:
//   - the JSON reader and writer (Json.mqh), with a fuzz
//   - every request of the bridge (Bridge.mqh) against the fake MT5, its refusals, and the same
//     orders at every broker profile against a server that applies that broker's rules
//   - the link (Link.mqh): which chart serves the panel, and the pipe end to end, byte for byte
// What the EA writes is read with a separate JSON reader, written here, so a broken writer can't
// hide behind its own reader. Exits with 1 when any check fails.
//   bridge [fuzz-iterations] [seed]
#include <random>
#include "mql.h"
#include "brokers.h"
#include <ActionInna/Link.mqh>

static int s_pass = 0;
static int s_fail = 0;
static std::string s_case;

static void Expect_(bool ok, const std::string &what, int line)
  {
   if(ok)
     {
      s_pass++;
      return;
     }
   s_fail++;
   if(s_fail <= 60)
      printf("FAIL [%s] %s (bridge.cpp:%d)\n", s_case.c_str(), what.c_str(), line);
  }
#define EXPECT(cond, what) Expect_((cond), (what), __LINE__)

static bool Near(double a, double b, double eps = 1e-9) { return std::fabs(a - b) <= eps; }
static void Advance(int ms) { g_fake.us += (ulong)ms * 1000ULL; }
static bool Has(const std::string &hay, const std::string &needle) { return hay.find(needle) != std::string::npos; }

//--- a JSON reader of its own ----------------------------------------------------
struct JV
  {
   enum Kind { NUL, BOOL, NUM, STR, ARR, OBJ } kind = NUL;
   bool b = false;
   double n = 0.0;
   std::string s;
   std::vector<JV> a;
   std::vector<std::pair<std::string, JV>> o;

   const JV &operator[](const std::string &k) const
     {
      static const JV none;
      for(auto &p : o)
         if(p.first == k) return p.second;
      return none;
     }
   const JV &at(size_t i) const
     {
      static const JV none;
      return i < a.size() ? a[i] : none;
     }
   bool has(const std::string &k) const
     {
      for(auto &p : o)
         if(p.first == k) return true;
      return false;
     }
  };

struct JP
  {
   const std::string &t;
   size_t p = 0;
   explicit JP(const std::string &text) : t(text) {}
   void ws() { while(p < t.size() && (t[p] == ' ' || t[p] == '\t' || t[p] == '\r' || t[p] == '\n')) p++; }
   bool lit(const char *w) { size_t n = strlen(w); if(t.compare(p, n, w) != 0) return false; p += n; return true; }
   bool str(std::string &out)
     {
      if(p >= t.size() || t[p] != '"') return false;
      p++;
      out.clear();
      while(p < t.size())
        {
         char c = t[p++];
         if(c == '"') return true;
         if((unsigned char)c < 0x20) return false;
         if(c != '\\') { out += c; continue; }
         if(p >= t.size()) return false;
         char e = t[p++];
         switch(e)
           {
            case '"': out += '"'; break;
            case '\\': out += '\\'; break;
            case '/': out += '/'; break;
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            case 'u':
              {
               if(p + 4 > t.size()) return false;
               unsigned v = 0;
               for(int k = 0; k < 4; k++)
                 {
                  char h = t[p++];
                  v <<= 4;
                  if(h >= '0' && h <= '9') v |= h - '0';
                  else if(h >= 'a' && h <= 'f') v |= h - 'a' + 10;
                  else if(h >= 'A' && h <= 'F') v |= h - 'A' + 10;
                  else return false;
                 }
               out += (v < 0x80) ? (char)v : '?';
               break;
              }
            default: return false;
           }
        }
      return false;
     }
   bool num(double &v)
     {
      size_t start = p;
      if(p < t.size() && t[p] == '-') p++;
      if(p < t.size() && t[p] == '0') p++;
      else
        {
         if(p >= t.size() || !isdigit((unsigned char)t[p])) return false;
         while(p < t.size() && isdigit((unsigned char)t[p])) p++;
        }
      if(p < t.size() && t[p] == '.')
        {
         p++;
         if(p >= t.size() || !isdigit((unsigned char)t[p])) return false;
         while(p < t.size() && isdigit((unsigned char)t[p])) p++;
        }
      if(p < t.size() && (t[p] == 'e' || t[p] == 'E'))
        {
         p++;
         if(p < t.size() && (t[p] == '+' || t[p] == '-')) p++;
         if(p >= t.size() || !isdigit((unsigned char)t[p])) return false;
         while(p < t.size() && isdigit((unsigned char)t[p])) p++;
        }
      v = strtod(t.substr(start, p - start).c_str(), nullptr);
      return true;
     }
   bool val(JV &v, int depth = 0)
     {
      if(depth > 32) return false;
      ws();
      if(p >= t.size()) return false;
      char c = t[p];
      if(c == '"') { v.kind = JV::STR; return str(v.s); }
      if(c == 't') { v.kind = JV::BOOL; v.b = true; return lit("true"); }
      if(c == 'f') { v.kind = JV::BOOL; v.b = false; return lit("false"); }
      if(c == 'n') { v.kind = JV::NUL; return lit("null"); }
      if(c == '[')
        {
         p++;
         v.kind = JV::ARR;
         ws();
         if(p < t.size() && t[p] == ']') { p++; return true; }
         while(true)
           {
            JV item;
            if(!val(item, depth + 1)) return false;
            v.a.push_back(item);
            ws();
            if(p < t.size() && t[p] == ',') { p++; continue; }
            if(p < t.size() && t[p] == ']') { p++; return true; }
            return false;
           }
        }
      if(c == '{')
        {
         p++;
         v.kind = JV::OBJ;
         ws();
         if(p < t.size() && t[p] == '}') { p++; return true; }
         while(true)
           {
            ws();
            std::string k;
            if(!str(k)) return false;
            ws();
            if(p >= t.size() || t[p] != ':') return false;
            p++;
            JV item;
            if(!val(item, depth + 1)) return false;
            v.o.push_back({k, item});
            ws();
            if(p < t.size() && t[p] == ',') { p++; continue; }
            if(p < t.size() && t[p] == '}') { p++; return true; }
            return false;
           }
        }
      v.kind = JV::NUM;
      return num(v.n);
     }
  };

static bool ParseJson(const std::string &text, JV &out)
  {
   out = JV();
   JP jp(text);
   if(!jp.val(out)) return false;
   jp.ws();
   return jp.p == text.size();
  }

//--- Json.mqh ----------------------------------------------------------------------
static void TestJsonReader()
  {
   s_case = "JSON reader";
   CAiJsonIn in;
   EXPECT(in.Parse(string("{\"t\":\"preview\",\"id\":12,\"x\":-1.5e2,\"ok\":true,\"no\":false,\"none\":null,\"s\":\"a\\\"b\\\\c\\nd\\u0041\"}")),
          "a flat object is read: " + in.Error().s);
   EXPECT(in.Str(string("t")) == string("preview") && in.Int(string("id"), 0) == 12, "string and whole number");
   EXPECT(Near(in.Num(string("x"), 0.0), -150.0), "a number with an exponent");
   EXPECT(in.Bool(string("ok"), false) && !in.Bool(string("no"), true) && in.Str(string("none"), string("dflt")) == string("dflt"), "true, false, null");
   EXPECT(in.Str(string("s")) == string("a\"b\\c\ndA"), "escapes are decoded: [" + in.Str(string("s")).s + "]");
   EXPECT(!in.Has(string("missing")) && in.Num(string("missing"), 7.0) == 7.0 && in.Int(string("t"), -3) == -3, "missing keys and wrong kinds give the default");
   EXPECT(in.Parse(string("  { \"a\" : { \"b\" : [1, {\"c\": \"]}\"}] } , \"z\" : 2 }  ")) && !in.Has(string("a")) && in.Int(string("z"), 0) == 2,
          "nested values are skipped whole, brackets inside strings too");
   EXPECT(in.Parse(string("{\"k\":1,\"k\":2}")) && in.Int(string("k"), 0) == 2, "the last of a repeated key wins");
   EXPECT(in.Parse(string("{}")) && !in.Has(string("t")), "an empty object");
   EXPECT(in.Parse(string("{\"ticket\":\"9876543210123\"}")) && in.Int(string("ticket"), 0) == 9876543210123LL, "a ticket written as a string");
   EXPECT(in.Parse(string("{\"v\":1.5}")) && in.Int(string("v"), -1) == -1, "a fraction is not a whole number");
   const char *bad[] = {"", "[]", "\"x\"", "{", "{\"a\"}", "{\"a\":}", "{\"a\":1,}", "{\"a\":1 \"b\":2}", "{'a':1}", "{\"a\":01}", "{\"a\":1.}",
                        "{\"a\":-}", "{\"a\":1e}", "{\"a\":\"x}", "{\"a\":\"\\q\"}", "{\"a\":\"\\u12g4\"}", "{\"a\":tru}", "{\"a\":1} x",
                        "{\"a\":[1,2}", "{\"a\":\"line\nbreak\"}"};
   for(const char *b : bad)
      EXPECT(!in.Parse(string(b)) && in.Error() != string(""), std::string("refused: ") + b);
  }

static void TestJsonWriter(std::mt19937 &rng)
  {
   s_case = "JSON writer";
   const std::string alphabet = "abcXYZ019 _-.,:;{}[]\"\\/\n\r\t\x01\x1f";
   for(int i = 0; i < 3000; i++)
     {
      std::string s;
      int len = (int)(rng() % 24);
      for(int k = 0; k < len; k++)
         s += alphabet[rng() % alphabet.size()];
      double v = std::uniform_real_distribution<double>(-1e6, 1e6)(rng);
      int digits = (int)(rng() % 9) - 1;
      CAiJsonOut o;
      o.Str(string("s"), string(s));
      o.Num(string("v"), v, digits);
      o.Open(string("list"), true);
      o.Int(string(""), (long)i);
      o.Str(string(""), string(s));
      o.Close(true);
      o.Bool(string("b"), (i % 2) == 0);
      std::string text = o.Text().s;
      JV j;
      bool ok = ParseJson(text, j);
      EXPECT(ok, "the writer writes valid JSON: " + text);
      if(!ok)
         continue;
      double unit = (digits < 0) ? 1e-8 : std::pow(10.0, -digits);
      EXPECT(j["s"].s == s && j["list"].at(1).s == s, "a string reads back as written");
      EXPECT(Near(j["v"].n, v, unit * 0.51 + 1e-9), "a number reads back within its last digit: " + text);
      EXPECT(j["list"].at(0).n == i && j["b"].b == ((i % 2) == 0), "array items and booleans read back");
      CAiJsonIn in;
      EXPECT(in.Parse(string(text)) && in.Str(string("s")).s == s, "the EA's own reader reads it back too");
     }
  }

static void FuzzJsonReader(std::mt19937 &rng, int iterations)
  {
   s_case = "JSON reader fuzz";
   const std::string alphabet = "{}[]\":,\\ tfnrue0123456789.-+eEu\"abc\n";
   const std::string valid = "{\"t\":\"preview\",\"id\":3,\"side\":\"buy\",\"slValue\":20.5,\"pending\":false,\"x\":[1,{\"y\":\"z\"}]}";
   int accepted = 0;
   for(int i = 0; i < iterations; i++)
     {
      std::string s;
      if(rng() % 2)
        {
         s = valid;
         int changes = 1 + (int)(rng() % 4);
         for(int k = 0; k < changes; k++)
            s[rng() % s.size()] = alphabet[rng() % alphabet.size()];
        }
      else
        {
         int len = (int)(rng() % 60);
         for(int k = 0; k < len; k++)
            s += alphabet[rng() % alphabet.size()];
        }
      CAiJsonIn in;
      bool mine = in.Parse(string(s));
      JV j;
      bool ref = ParseJson(s, j) && j.kind == JV::OBJ;
      if(mine)
         accepted++;
      EXPECT(mine == ref, "accepts exactly what a JSON reader accepts: " + s + " (EA " + (mine ? "yes" : "no: " + in.Error().s) + ")");
      EXPECT(mine || in.Error() != string(""), "a refusal says why");
     }
   EXPECT(accepted > 0, "the fuzz also produced valid objects");
  }

//--- the bridge ----------------------------------------------------------------------
static AiSettings Cfg()
  {
   AiSettings c;
   ZeroMemory(c);
   c.preset[0] = 1.0;
   c.preset[1] = 1.5;
   c.preset[2] = 2.0;
   c.riskBase = AI_BASE_EQUITY;
   c.maxRiskPct = 5.0;
   c.requireSL = true;
   c.requireTP = true;
   c.defaultSLPips = 20.0;
   c.defaultTPMode = AI_LEVEL_RR;
   c.defaultTPValue = 2.0;
   c.pipMode = AI_PIP_TRADER;
   c.pendingOffsetPips = 10.0;
   c.deviation = 10;
   c.comment = "ActionInna";
   return c;
  }

static CAiBridge s_b;
static std::vector<JV> s_pushed;   // what the bridge queued by itself since the last request
static int s_nextId = 100;

static std::vector<JV> Drain()
  {
   MqlArray<string> out;
   int n = s_b.TakeOut(out);
   std::vector<JV> got;
   for(int i = 0; i < n; i++)
     {
      JV v;
      bool ok = ParseJson(out[i].s, v);
      EXPECT(ok && v.kind == JV::OBJ && v.has("t"), "the bridge writes valid JSON objects with a type: " + out[i].s);
      if(ok)
         got.push_back(v);
     }
   return got;
  }

// Sends one request and returns its reply; whatever else came out is kept in s_pushed.
static JV Req(const std::string &type, const std::string &fields)
  {
   int id = ++s_nextId;
   std::string json = "{\"t\":\"" + type + "\",\"id\":" + std::to_string(id) + (fields.empty() ? "" : "," + fields) + "}";
   s_b.Handle(string(json));
   std::vector<JV> got = Drain();
   JV reply;
   int replies = 0;
   s_pushed.clear();
   for(auto &v : got)
     {
      if(v["t"].s == "reply" && (int)v["id"].n == id)
        {
         reply = v;
         replies++;
        }
      else
         s_pushed.push_back(v);
     }
   EXPECT(replies == 1, "exactly one reply to " + json + " (got " + std::to_string(replies) + ")");
   return reply;
  }

static std::string PreviewFields(const std::string &symbol, const std::string &side, bool pending = false, double entry = 0.0,
                                 const std::string &slMode = "pips", double sl = 20.0, const std::string &tpMode = "r", double tp = 2.0,
                                 const std::string &riskMode = "percent", double risk = 1.0)
  {
   char b[512];
   snprintf(b, sizeof b, "\"symbol\":\"%s\",\"side\":\"%s\",\"pending\":%s,\"entry\":%.10g,\"slMode\":\"%s\",\"slValue\":%.10g,\"tpMode\":\"%s\","
            "\"tpValue\":%.10g,\"riskMode\":\"%s\",\"riskValue\":%.10g,\"riskBase\":\"equity\"", symbol.c_str(), side.c_str(),
            pending ? "true" : "false", entry, slMode.c_str(), sl, tpMode.c_str(), tp, riskMode.c_str(), risk);
   return b;
  }

static std::string Quoted(const std::string &k, const std::string &v) { return "\"" + k + "\":\"" + v + "\""; }
static std::string Field(const std::string &k, double v) { char b[128]; snprintf(b, sizeof b, "\"%s\":%.12g", k.c_str(), v); return b; }

static void SetUpBridge(const std::string &name, const BrokerProfile *broker = nullptr, const SymCase *sym = nullptr)
  {
   s_case = name;
   g_fake.Reset();
   if(sym)
      SetUpSymbol(*sym);
   else
      _Symbol = string(g_fake.sym.name);
   if(broker)
      ApplyBroker(*broker);
   s_b.Init(Cfg());
  }

static void AddPos(ulong t, int type, double vol, double open, double sl, double tp, int64_t timeMsc)
  {
   g_fake.pos.push_back(FakePos{t, type, vol, open, sl, tp, 0.0, timeMsc, g_fake.sym.name});
  }

static void ServerRefusedNothing()
  {
   for(uint code : g_fake.refusals)
      EXPECT(code == TRADE_RETCODE_REQUOTE, "the server refused nothing the bridge sent (got " + std::to_string(code) + ")");
   g_fake.refusals.clear();
  }

static void TestStartAndPushes()
  {
   SetUpBridge("the terminal, quotes and trades");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900, 1);
   s_b.Start();
   std::vector<JV> got = Drain();
   EXPECT(got.size() == 2 && got[0]["t"].s == "terminal" && got[1]["t"].s == "trades", "the panel learns the terminal and the trades at once");
   if(got.size() == 2)
     {
      const JV &t = got[0];
      EXPECT(t["login"].n == 12345678 && t["server"].s == "FakeServer" && t["currency"].s == "USD" && t["tradeMode"].s == "demo" &&
             t["marginMode"].s == "hedging" && t["hedgeAllowed"].b && !t["fifo"].b && t["connected"].b && t["problem"].s == "",
             "the terminal's account");
      EXPECT(t["settings"]["presets"].a.size() == 3 && t["settings"]["presets"].at(1).n == 1.5 && t["settings"]["maxRiskPct"].n == 5 &&
             t["settings"]["requireSL"].b && t["settings"]["pipMode"].s == "trader" && t["settings"]["slipPolicy"].s == "follow",
             "the EA's settings, which the panel shows but can't change");
      const JV &l = got[1]["list"];
      EXPECT(l.a.size() == 1 && l.at(0)["ticket"].n == 101 && l.at(0)["kind"].s == "position" && l.at(0)["type"].s == "BUY" &&
             Near(l.at(0)["sl"].n, 1.07750) && l.at(0)["symbol"].s == "EURUSD" && got[1]["balance"].n == 10000, "the open position");
     }
   g_fake.termTrade = false;
   Advance(1100);
   s_b.Poll();
   got = Drain();
   bool sawProblem = false;
   for(auto &v : got)
      if(v["t"].s == "terminal" && Has(v["problem"].s, "Algo Trading"))
         sawProblem = true;
   EXPECT(sawProblem, "the terminal is sent again when something in it changes");
   g_fake.termTrade = true;

   JV w = Req("watch", Quoted("symbol", "EURUSD"));
   EXPECT(w["ok"].b && w["spec"]["digits"].n == 5 && Near(w["spec"]["pipSize"].n, 0.0001) && w["spec"]["execution"].s == "market" &&
          w["spec"]["orders"]["sl"].b && w["spec"]["base"].s == "EUR", "watch: the symbol's details");
   s_b.Poll();
   got = Drain();
   int quotes = 0;
   for(auto &v : got)
      if(v["t"].s == "quote")
        {
         quotes++;
         EXPECT(v["symbol"].s == "EURUSD" && Near(v["bid"].n, 1.08480) && Near(v["ask"].n, 1.08500) && Near(v["spreadPips"].n, 2.0), "a quote");
        }
   EXPECT(quotes == 1, "the first quote comes at once");
   g_fake.sym.bid = 1.08490;
   g_fake.sym.ask = 1.08510;
   Advance(50);
   s_b.Poll();
   got = Drain();
   quotes = 0;
   for(auto &v : got)
      quotes += (v["t"].s == "quote");
   EXPECT(quotes == 0, "at most ten quotes a second");
   Advance(60);
   s_b.Poll();
   got = Drain();
   quotes = 0;
   for(auto &v : got)
      quotes += (v["t"].s == "quote");
   EXPECT(quotes == 1, "a new price, a new quote");
   Advance(150);
   s_b.Poll();
   got = Drain();
   quotes = 0;
   for(auto &v : got)
      quotes += (v["t"].s == "quote");
   EXPECT(quotes == 0, "no quote while the price stands still");
   JV bad = Req("watch", Quoted("symbol", "NOPE"));
   EXPECT(!bad["ok"].b && Has(bad["err"].s, "Unknown symbol"), "an unknown symbol is refused");
  }

static void TestSymbols()
  {
   SetUpBridge("TradingView tickers to the broker's symbols");
   g_fake.others = {{"XAUUSDm", "Gold", "XAU", "USD", true}, {"#XAUUSD", "Gold spot", "XAU", "USD", false}, {"GOLD.c", "Gold CFD", "", "", false},
                    {"EURUSDm", "Euro", "EUR", "USD", false}, {"US30.cash", "Dow Jones", "USD", "USD", true}, {"EURGBP", "Euro vs Pound", "EUR", "GBP", false},
                    {"XAGUSD", "Silver", "XAG", "USD", false}, {"EURUSDT", "Euro vs Tether", "EUR", "USDT", false}};
   JV r = Req("symbols", Quoted("ticker", "FX:EURUSD"));
   EXPECT(r["ok"].b && r["ticker"].s == "EURUSD" && r["pick"].s == "EURUSD", "the same name is the pick: " + r["pick"].s);
   EXPECT(r["candidates"].at(0)["name"].s == "EURUSD" && r["candidates"].at(0)["rank"].n == 0, "and comes first");
   bool suffix = false;
   for(auto &c : r["candidates"].a)
      if(c["name"].s == "EURUSDm" && c["rank"].n == 2) suffix = true;
   EXPECT(suffix, "a suffixed name is a candidate");
   r = Req("symbols", Quoted("ticker", "OANDA:XAUUSD"));
   EXPECT(r["pick"].s == "#XAUUSD", "the same letters behind a prefix win: " + r["pick"].s);
   EXPECT(r["candidates"].a.size() == 3 && r["candidates"].at(1)["name"].s == "XAUUSDm" && r["candidates"].at(2)["name"].s == "GOLD.c",
          "then the suffix, then another name for gold");
   r = Req("symbols", Quoted("ticker", "TVC:DJI"));
   EXPECT(r["pick"].s == "US30.cash", "the Dow under the broker's name: " + r["pick"].s);
   r = Req("symbols", Quoted("ticker", "XAGUSD"));
   EXPECT(r["pick"].s == "XAGUSD", "silver");
   r = Req("pick", Quoted("ticker", "OANDA:XAUUSD") + "," + Quoted("symbol", "XAUUSDm"));
   EXPECT(r["ok"].b, "the trader's choice is kept");
   r = Req("symbols", Quoted("ticker", "XAUUSD"));
   EXPECT(r["pick"].s == "XAUUSDm", "and comes back: " + r["pick"].s);
   r = Req("pick", Quoted("ticker", "XAUUSD") + "," + Quoted("symbol", "NOPE"));
   EXPECT(!r["ok"].b, "a symbol the broker doesn't have can't be chosen");
   r = Req("symbols", Quoted("ticker", "NASDAQ:AAPL"));
   EXPECT(r["ok"].b && r["candidates"].a.empty() && r["pick"].s == "", "a ticker the broker doesn't have: no candidates");
  }

static void TestOrders()
  {
   SetUpBridge("preview, then send");
   s_b.Start();
   Drain();
   JV p = Req("preview", PreviewFields("EURUSD", "buy"));
   EXPECT(p["ok"].b && p["plan"]["valid"].b && Near(p["plan"]["lots"].n, 0.50) && Near(p["plan"]["riskMoney"].n, 100.0) &&
          Near(p["plan"]["sl"].n, 1.08300) && Near(p["plan"]["tp"].n, 1.08900) && p["plan"]["type"].s == "BUY",
          "a BUY at 1% with a 20-pip stop: 0.50 lots, $100");
   EXPECT(g_fake.requests.empty(), "a preview sends nothing");
   std::string pid = p["preview"].s;
   JV s = Req("send", Quoted("preview", pid));
   EXPECT(s["ok"].b && g_fake.requests.size() == 1 && g_fake.requests[0].action == TRADE_ACTION_DEAL && g_fake.requests[0].sl > 0.0 &&
          g_fake.requests[0].tp > 0.0, "send: one market order with its SL and TP");
   EXPECT(s["type"].s == "BUY" && !s["fill"]["slipped"].b && Near(s["price"].n, 1.08500) && g_fake.pos.size() == 1, "filled as planned");
   JV again = Req("send", Quoted("preview", pid));
   EXPECT(!again["ok"].b && Has(again["err"].s, "already confirmed") && g_fake.requests.size() == 1, "a preview is sent once");
   JV unknown = Req("send", Quoted("preview", "p999"));
   EXPECT(!unknown["ok"].b && Has(unknown["err"].s, "Unknown preview"), "an unknown preview is refused");

   p = Req("preview", PreviewFields("EURUSD", "sell"));
   Advance(61000);
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "more than a minute old") && g_fake.requests.size() == 1, "a preview older than a minute is refused");

   p = Req("preview", PreviewFields("EURUSD", "sell"));
   g_fake.login = 87654321;
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "another account") && g_fake.requests.size() == 1, "an account switch since the preview is refused");
   g_fake.login = 12345678;

   // Fixed lots and an SL set as a price: when the price moves away from the stop, the risk grows.
   p = Req("preview", PreviewFields("EURUSD", "buy", false, 0.0, "price", 1.08300, "r", 2.0, "lots", 0.5));
   g_fake.sym.ask += 0.00020;
   g_fake.sym.bid += 0.00020;
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "risk grew") && g_fake.requests.size() == 1, "a risk 10% above the preview's is refused: " + s["err"].s);
   g_fake.sym.ask -= 0.00020;
   g_fake.sym.bid -= 0.00020;

   p = Req("preview", PreviewFields("EURUSD", "buy", false, 0.0, "pips", 0.0));
   EXPECT(p["ok"].b && !p["plan"]["valid"].b && p["plan"]["err"].s != "", "an invalid plan says why");
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && g_fake.requests.size() == 1, "and can't be sent");

   g_fake.termTrade = false;
   p = Req("preview", PreviewFields("EURUSD", "buy"));
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "Algo Trading") && g_fake.requests.size() == 1, "nothing is sent while MT5 forbids it");
   g_fake.termTrade = true;

   g_fake.slip = 0.00030;
   p = Req("preview", PreviewFields("EURUSD", "buy"));
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(s["ok"].b && s["fill"]["slipped"].b && Near(s["fill"]["slipPips"].n, 3.0) && s["fill"]["slMoved"].b && Near(s["fill"]["risk"].n, 100.0, 0.01),
          "a slipped fill: SL and TP follow, the risk stays $100");
   g_fake.slip = 0.0;

   p = Req("preview", PreviewFields("EURUSD", "buy", true, 1.08300));
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(p["plan"]["type"].s == "BUY LIMIT" && s["ok"].b && s["pending"].b && g_fake.ords.size() == 1, "a pending BUY LIMIT is placed");

   JV r = Req("recall", Quoted("symbol", "EURUSD") + "," + Quoted("side", "buy"));
   EXPECT(r["ok"].b && r["slMode"].s == "pips" && Near(r["slValue"].n, 20.0) && r["tpMode"].s == "r" && Near(r["tpValue"].n, 2.0) && r["count"].n >= 1,
          "recall: the SL/TP of the last order: " + r["desc"].s);
   ServerRefusedNothing();

   JV x = Req("preview", Quoted("symbol", "EURUSD") + "," + Quoted("side", "up"));
   EXPECT(!x["ok"].b && Has(x["err"].s, "side"), "a side that isn't buy or sell is refused");
   x = Req("preview", PreviewFields("EURUSD", "buy", false, 0.0, "r", 20.0));
   EXPECT(!x["ok"].b, "an SL in R is refused");
   x = Req("fly", "");
   EXPECT(!x["ok"].b && Has(x["err"].s, "Unknown request"), "an unknown request is refused");
   s_b.Handle(string("not json"));
   std::vector<JV> got = Drain();
   EXPECT(got.size() == 1 && got[0]["t"].s == "error" && got[0]["err"].s != "", "a frame that isn't JSON gets an error back");
   s_b.Handle(string("{\"t\":\"preview\"}"));
   got = Drain();
   EXPECT(got.size() == 1 && got[0]["t"].s == "error", "a request without an id gets an error back");
  }

static void TestRecall()
  {
   SetUpBridge("recall: the levels asked for, from the records that hold them");
   g_fake.others = {{"GBPUSD", "Pound", "GBP", "USD", true}};
   s_b.Start();
   Drain();
   // Newest first: a record with only a TP of 60 pips, then one with an SL of 30 pips and a TP of 2R.
   AiMem tpOnly;
   ZeroMemory(tpOnly);
   tpOnly.t = 2000;
   tpOnly.side = AI_BUY;
   tpOnly.slMode = AI_LEVEL_PIPS;
   tpOnly.tpMode = AI_LEVEL_PIPS;
   tpOnly.tpDist = 0.00600;
   AiMem both;
   ZeroMemory(both);
   both.t = 1000;
   both.side = AI_BUY;
   both.slMode = AI_LEVEL_PIPS;
   both.slDist = 0.00300;
   both.tpMode = AI_LEVEL_RR;
   both.tpDist = 0.00600;
   both.tpR = 2.0;
   MqlArray<AiMem> mem;
   ArrayResize(mem, 2);
   mem[0] = tpOnly;
   mem[1] = both;
   EXPECT(AiMemSave("EURUSD", mem), "two records saved");
   std::string buy = Quoted("symbol", "EURUSD") + "," + Quoted("side", "buy");

   JV r = Req("recall", buy + "," + Quoted("which", "sl"));
   EXPECT(r["ok"].b && r["index"].n == 1 && r["count"].n == 2 && r["slMode"].s == "pips" && Near(r["slValue"].n, 30.0) && r["desc"].s == "SL 30 pips",
          "SL Last skips the record without a stop, and names only the stop: " + r["desc"].s);
   r = Req("recall", buy + "," + Quoted("which", "tp"));
   EXPECT(r["ok"].b && r["index"].n == 0 && r["tpMode"].s == "pips" && Near(r["tpValue"].n, 60.0) && r["desc"].s == "TP 60 pips",
          "TP Last takes the newest: " + r["desc"].s);
   r = Req("recall", buy + "," + Quoted("which", "tp") + "," + Field("back", 1));
   EXPECT(r["ok"].b && r["index"].n == 1 && r["tpMode"].s == "r" && Near(r["tpValue"].n, 2.0) && r["desc"].s == "TP 2R",
          "the next press goes one record further back: " + r["desc"].s);
   r = Req("recall", buy + "," + Quoted("which", "sl") + "," + Field("back", 2));
   EXPECT(r["ok"].b && r["index"].n == 1, "back wraps around, still skipping");
   r = Req("recall", buy);
   EXPECT(r["ok"].b && r["index"].n == 0 && r["desc"].s == "TP 60 pips", "both levels by default, as far as the record holds them: " + r["desc"].s);
   r = Req("recall", Quoted("symbol", "GBPUSD") + "," + Quoted("side", "buy") + "," + Quoted("which", "sl"));
   EXPECT(!r["ok"].b && Has(r["err"].s, "No earlier stop loss saved for GBPUSD"), "a symbol with no records and no trades: " + r["err"].s);
  }

static void TestChangesClosesCancels()
  {
   SetUpBridge("changes, closes and removals");
   AddPos(201, POSITION_TYPE_BUY, 0.50, 1.08000, 1.07750, 1.08900, 1000);
   g_fake.ords.push_back(FakeOrd{301, ORDER_TYPE_BUY_LIMIT, 0.10, 1.08300, 1.08100, 1.08700, 0.0, ORDER_TIME_GTC, 0, g_fake.sym.name});
   s_b.Start();
   Drain();

   JV m = Req("modPreview", Field("ticket", 201) + "," + Field("sl", 1.07850) + "," + Field("tp", 1.08900));
   EXPECT(m["ok"].b && m["mod"]["valid"].b && m["mod"]["changed"].b && Near(m["mod"]["sl"].n, 1.07850) && Near(m["mod"]["slMoney"].n, -75.0, 0.01),
          "a tighter stop: valid, $75 at risk");
   JV s = Req("modSend", Quoted("preview", m["preview"].s));
   EXPECT(s["ok"].b && g_fake.requests.size() == 1 && g_fake.requests[0].action == TRADE_ACTION_SLTP && Near(g_fake.pos[0].sl, 1.07850),
          "modSend: the server has the new SL");
   s = Req("modSend", Quoted("preview", m["preview"].s));
   EXPECT(!s["ok"].b && g_fake.requests.size() == 1, "a change is sent once");

   m = Req("modPreview", Field("ticket", 201) + "," + Field("sl", 1.07900) + "," + Field("tp", 1.08900));
   g_fake.pos[0].tp = 1.09000;
   s = Req("modSend", Quoted("preview", m["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "changed since the preview") && g_fake.requests.size() == 1, "a trade changed elsewhere is not overwritten");

   m = Req("modPreview", Field("ticket", 201) + "," + Field("sl", 1.08490) + "," + Field("tp", 1.09000));
   EXPECT(m["ok"].b && !m["mod"]["valid"].b && Has(m["mod"]["err"].s, "below the price"), "a buy's SL above the bid: refused in the preview");
   s = Req("modSend", Quoted("preview", m["preview"].s));
   EXPECT(!s["ok"].b && g_fake.requests.size() == 1, "and not sent");

   m = Req("modPreview", Field("ticket", 301) + "," + Field("open", 1.08200) + "," + Field("sl", 1.08000) + "," + Field("tp", 1.08600));
   s = Req("modSend", Quoted("preview", m["preview"].s));
   EXPECT(s["ok"].b && g_fake.requests.back().action == TRADE_ACTION_MODIFY && Near(g_fake.ords[0].price, 1.08200), "a pending order's entry moves");

   JV c = Req("closePreview", Field("ticket", 201) + "," + Field("lots", 0.20));
   EXPECT(c["ok"].b && c["close"]["valid"].b && Near(c["close"]["left"].n, 0.30) && Near(c["close"]["price"].n, 1.08480), "part close: 0.30 lots stay");
   size_t before = g_fake.requests.size();
   s = Req("close", Quoted("preview", c["preview"].s));
   EXPECT(s["ok"].b && g_fake.requests.size() == before + 1 && g_fake.requests.back().position == 201 && Near(g_fake.requests.back().volume, 0.20) &&
          g_fake.requests.back().type == ORDER_TYPE_SELL && Near(g_fake.pos[0].volume, 0.30), "close: a SELL of 0.20 tied to #201");
   s = Req("close", Quoted("preview", c["preview"].s));
   EXPECT(!s["ok"].b && g_fake.requests.size() == before + 1, "a close is sent once");
   c = Req("closePreview", Field("ticket", 201) + "," + Field("lots", 0.295));
   EXPECT(!c["close"]["valid"].b && Has(c["close"]["err"].s, "multiple"), "lots off the volume step are refused");
   c = Req("closePreview", Field("ticket", 201) + "," + Field("lots", 0.40));
   EXPECT(!c["close"]["valid"].b && Has(c["close"]["err"].s, "only 0.30"), "more lots than the position has are refused");
   c = Req("closePreview", Field("ticket", 201) + "," + Field("lots", 0.0));
   EXPECT(c["close"]["valid"].b && Near(c["close"]["lots"].n, 0.30) && Near(c["close"]["left"].n, 0.0), "lots 0 closes all of it");
   c = Req("closePreview", Field("ticket", 301));
   EXPECT(!c["ok"].b, "a pending order is not closed");

   JV x = Req("cancel", Field("ticket", 301));
   EXPECT(x["ok"].b && g_fake.requests.back().action == TRADE_ACTION_REMOVE && g_fake.ords.empty(), "cancel removes the pending order");
   x = Req("cancel", Field("ticket", 301));
   EXPECT(!x["ok"].b && Has(x["err"].s, "not a pending order"), "and can't remove it twice");
   g_fake.ords.push_back(FakeOrd{302, ORDER_TYPE_BUY_LIMIT, 0.10, 1.08490, 1.08300, 1.08800, 0.0, ORDER_TIME_GTC, 0, g_fake.sym.name});
   g_fake.sym.freeze = 30;
   x = Req("cancel", Field("ticket", 302));
   EXPECT(!x["ok"].b && Has(x["err"].s, "freeze level") && g_fake.ords.size() == 1, "a pending order inside the freeze level stays");
   g_fake.sym.freeze = 0;
   ServerRefusedNothing();
  }

static void TestFifo()
  {
   SetUpBridge("an account that closes first in, first out", &kBrokers[3]);
   AddPos(401, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900, 1000);
   AddPos(402, POSITION_TYPE_BUY, 0.10, 1.08100, 1.07850, 1.09000, 2000);
   s_b.Start();
   Drain();
   JV c = Req("closePreview", Field("ticket", 402));
   EXPECT(!c["close"]["valid"].b && Has(c["close"]["err"].s, "close #401 first"), "the newer position waits for the older: " + c["close"]["err"].s);
   JV s = Req("close", Quoted("preview", c["preview"].s));
   EXPECT(!s["ok"].b && g_fake.requests.empty(), "and is not sent");
   c = Req("closePreview", Field("ticket", 401));
   s = Req("close", Quoted("preview", c["preview"].s));
   EXPECT(s["ok"].b && g_fake.pos.size() == 1 && g_fake.pos[0].ticket == 402, "the oldest closes");
   ServerRefusedNothing();
  }

// The same orders at every broker profile: each is accepted by that broker's server, or refused in
// the preview with the reason.
static void TestBrokers()
  {
   for(int b = 0; b < kBrokerCount; b++)
      for(int j = 0; j < kSymCount; j++)
        {
         const BrokerProfile &pr = kBrokers[b];
         SetUpBridge(std::string("broker ") + pr.name + ", " + kSyms[j].name, &pr, &kSyms[j]);
         s_b.Start();
         Drain();
         std::string sym = _Symbol.s;
         double pip = (std::string(kSyms[j].base) == "XAU") ? 0.1 : ((kSyms[j].digits == 3 || kSyms[j].digits == 5) ? kSyms[j].point * 10.0 : kSyms[j].point);
         double slPips = std::max(30.0, (kSyms[j].stops + 10) * kSyms[j].point / pip);
         for(int k = 0; k < 4; k++)
           {
            bool pending = (k >= 2);
            std::string side = (k % 2 == 0) ? "buy" : "sell";
            double market = (side == "buy") ? g_fake.sym.ask : g_fake.sym.bid;
            double entry = pending ? market + ((side == "buy") ? -1.0 : 1.0) * slPips * pip : 0.0;
            JV p = Req("preview", PreviewFields(sym, side, pending, entry, "pips", slPips));
            if(!p["plan"]["valid"].b)
              {
               EXPECT(p["plan"]["err"].s != "", "a refused plan says why");
               continue;
              }
            size_t before = g_fake.requests.size();
            JV s = Req("send", Quoted("preview", p["preview"].s));
            EXPECT(s["ok"].b || s["err"].s != "", "a send succeeds or says why");
            if(!s["ok"].b)
               EXPECT(Has(s["err"].s, "allows no opposite positions"), "a refused send is one the account forbids: " + s["err"].s);
            if(s["ok"].b)
               EXPECT(g_fake.requests.size() > before, "a send that succeeds reached the server");
           }
         ServerRefusedNothing();
        }
  }

//--- the link ---------------------------------------------------------------------------
static void TestHostElection()
  {
   s_case = "which chart serves the panel";
   g_fake.Reset();
   CAiLinkHost a, b;
   a.Init(11.0);
   b.Init(22.0);
   EXPECT(a.Update(100.0) && !b.Update(100.0), "the first chart serves, the second waits");
   EXPECT(a.Update(101.0) && !b.Update(102.0), "while the first one beats");
   EXPECT(!b.Update(103.5), "a heartbeat 2.5 s old is still alive");
   EXPECT(b.Update(104.5) && b.IsHost(), "after 3 s without a beat, the second takes over");
   EXPECT(!a.Update(104.6) && !a.IsHost(), "and the first one learns it at its next update");
   b.Release();
   EXPECT(a.Update(104.7), "a chart that stops serving lets another take over at once");
   CAiLinkHost c;
   c.Init(33.0);
   EXPECT(!c.Update(104.8) && a.IsHost(), "a third chart waits too");
  }

static void PushFrame(const std::string &json)
  {
   uint32_t n = (uint32_t)json.size();
   for(int i = 0; i < 4; i++)
      g_fake.pipe.toEa += (char)((n >> (8 * i)) & 0xFF);
   g_fake.pipe.toEa += json;
  }

static std::vector<JV> PipeFrames()
  {
   std::vector<JV> got;
   std::string &q = g_fake.pipe.fromEa;
   while(q.size() >= 4)
     {
      uint32_t n = (uint8_t)q[0] | ((uint8_t)q[1] << 8) | ((uint8_t)q[2] << 16) | ((uint32_t)(uint8_t)q[3] << 24);
      if(q.size() < 4 + n)
         break;
      JV v;
      EXPECT(ParseJson(q.substr(4, n), v), "a frame from the EA is JSON: " + q.substr(4, n));
      got.push_back(v);
      q.erase(0, 4 + n);
     }
   EXPECT(q.empty(), "the EA writes whole frames");
   return got;
  }

static int CountType(const std::vector<JV> &v, const std::string &t)
  {
   int n = 0;
   for(auto &x : v)
      n += (x["t"].s == t);
   return n;
  }

static const char *kKey = "0f1e2d3c4b5a69788796a5b4c3d2e1f0";

static void SetKeyFile(const char *key)
  {
   const std::string path = std::string("common:ActionInna") + (char)92 + "link.key";
   if(key)
      g_fake.files[path] = std::string(key) + "\r\n";
   else
      g_fake.files.erase(path);
  }

// The key the link program sends first; until it matches link.key, the EA serves nothing.
static void TestLinkKey()
  {
   s_case = "the link's key";
   g_fake.Reset();
   _Symbol = string(g_fake.sym.name);
   SetKeyFile(kKey);
   g_fake.pipe.serving = true;
   CAiLink link;
   link.Init(Cfg(), true);
   PushFrame("{\"t\":\"link\",\"key\":\"not-the-right-key-at-all\"}");
   PushFrame("{\"t\":\"watch\",\"id\":1,\"symbol\":\"EURUSD\"}");
   link.Timer();
   EXPECT(g_fake.pipe.fromEa.empty(), "a wrong key: the EA says nothing and serves nothing");
   g_fake.pipe.toEa.clear();
   Advance(2100);
   link.Timer();
   Advance(3100);
   link.Timer();
   EXPECT(g_fake.pipe.fromEa.empty(), "no key within 3 s: still nothing");
   g_fake.pipe.toEa.clear();
   SetKeyFile(nullptr);
   Advance(2100);
   link.Timer();
   PushFrame(std::string("{\"t\":\"link\",\"key\":\"") + kKey + "\"}");
   Advance(25);
   link.Timer();
   EXPECT(g_fake.pipe.fromEa.empty(), "no link.key on this PC: nothing is served, whatever the link sends");
   link.Deinit();
  }

static void TestLinkEndToEnd()
  {
   s_case = "the link over the pipe";
   g_fake.Reset();
   _Symbol = string(g_fake.sym.name);
   SetKeyFile(kKey);
   CAiLink link;
   link.Init(Cfg(), true);
   link.Timer();
   EXPECT(g_fake.pipe.fromEa.empty(), "no link running: nothing written, nothing breaks");
   g_fake.pipe.serving = true;
   Advance(2100);
   link.Timer();
   EXPECT(g_fake.pipe.fromEa.empty(), "connected, but nothing until the key arrives");
   PushFrame(std::string("{\"t\":\"link\",\"key\":\"") + kKey + "\"}");
   Advance(25);
   link.Timer();
   std::vector<JV> got = PipeFrames();
   EXPECT(CountType(got, "terminal") == 1 && CountType(got, "trades") == 1, "with the right key, the EA introduces itself");

   std::string preview = "{\"t\":\"preview\",\"id\":7," + PreviewFields("EURUSD", "buy") + "}";
   std::string frame;
   {
      uint32_t n = (uint32_t)preview.size();
      for(int i = 0; i < 4; i++)
         frame += (char)((n >> (8 * i)) & 0xFF);
      frame += preview;
   }
   g_fake.pipe.toEa += frame.substr(0, 9);
   Advance(25);
   link.Timer();
   got = PipeFrames();
   EXPECT(CountType(got, "reply") == 0, "half a frame waits");
   g_fake.pipe.toEa += frame.substr(9);
   Advance(25);
   link.Timer();
   got = PipeFrames();
   bool replied = false;
   std::string pid;
   for(auto &v : got)
      if(v["t"].s == "reply" && v["id"].n == 7 && v["plan"]["valid"].b)
        {
         replied = true;
         pid = v["preview"].s;
        }
   EXPECT(replied, "the whole frame is answered");
   PushFrame("{\"t\":\"send\",\"id\":8," + Quoted("preview", pid) + "}");
   PushFrame("{\"t\":\"watch\",\"id\":9," + Quoted("symbol", "EURUSD") + "}");
   Advance(25);
   link.Timer();
   got = PipeFrames();
   int okReplies = 0;
   for(auto &v : got)
      if(v["t"].s == "reply" && v["ok"].b)
         okReplies++;
   EXPECT(okReplies == 2 && g_fake.pos.size() == 1, "two frames in one read: both answered, the order filled");
   EXPECT(CountType(got, "trades") == 1, "the trades follow the fill at once");

   Advance(1100);
   link.Timer();
   got = PipeFrames();
   EXPECT(CountType(got, "beat") + CountType(got, "trades") + CountType(got, "quote") >= 1, "the EA writes at least once a second");
   for(int i = 0; i < 3; i++)
     {
      Advance(400);
      link.Timer();
     }
   got = PipeFrames();
   EXPECT(!got.empty(), "while positions are open, their profit keeps coming");

   g_fake.pipe.serving = false;
   g_fake.pipe.fromEa.clear();
   Advance(1100);
   link.Timer();
   g_fake.pipe.serving = true;
   Advance(500);
   link.Timer();
   EXPECT(g_fake.pipe.fromEa.empty(), "after the link went away, the EA waits before opening again");
   Advance(2100);
   link.Timer();
   PushFrame(std::string("{\"t\":\"link\",\"key\":\"") + kKey + "\"}");
   Advance(25);
   link.Timer();
   got = PipeFrames();
   EXPECT(CountType(got, "terminal") == 1, "and introduces itself again when it reconnects");

   link.Deinit();
   CAiLink off;
   off.Init(Cfg(), false);
   g_fake.pipe.fromEa.clear();
   off.Timer();
   Advance(2100);
   off.Timer();
   EXPECT(g_fake.pipe.fromEa.empty(), "switched off by its input: never connects");
  }

int main(int argc, char **argv)
  {
   MqlTrapZeroDivide();
   int iterations = (argc > 1) ? atoi(argv[1]) : 20000;
   unsigned seed = (argc > 2) ? (unsigned)atoi(argv[2]) : 20261025u;
   std::mt19937 rng(seed);
   TestJsonReader();
   TestJsonWriter(rng);
   FuzzJsonReader(rng, iterations);
   int jsonChecks = s_pass + s_fail;
   int jsonFails = s_fail;
   printf("json: %d checks, %d failed\n", jsonChecks, jsonFails);

   TestStartAndPushes();
   TestSymbols();
   TestOrders();
   TestRecall();
   TestChangesClosesCancels();
   TestFifo();
   TestBrokers();
   int bridgeChecks = s_pass + s_fail - jsonChecks;
   int bridgeFails = s_fail - jsonFails;
   printf("bridge: %d checks over %d broker profiles, %d failed\n", bridgeChecks, kBrokerCount, bridgeFails);

   TestHostElection();
   TestLinkKey();
   TestLinkEndToEnd();
   printf("link: %d checks, %d failed\n", s_pass + s_fail - jsonChecks - bridgeChecks, s_fail - jsonFails - bridgeFails);
   return s_fail ? 1 : 0;
  }
