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

//--- changes to open trades, fuzzed ---------------------------------------------------------
// Changes through the panel's own requests (modPreview, then modSend) at every broker set-up and
// symbol, with random prices, trades and levels: break-even and stops past it, levels at, inside
// and across the stops level, pending entries moved across the market (a limit becoming a stop),
// to the market price, off the tick grid, expiries a new order may or may not carry. The EA's
// answer is checked both ways against what the fake server takes:
//   - a change the preview allows goes through, and the server then has exactly what was previewed;
//   - a change the server would take is not refused by the preview.
// The safety cap is off here (it has its own tests); SL and TP are required, as by default.
static bool BuyType(int t) { return t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_BUY_STOP; }

static std::string Px(double v) { char b[64]; snprintf(b, sizeof b, "%.10g", v); return b; }

struct ChangeStats { int changes = 0, allowed = 0, retyped = 0, breakEven = 0, breakEvenRefused = 0; };

static void FuzzChanges(std::mt19937 &rng, int rounds, ChangeStats &st)
  {
   auto I = [&](int lo, int hi) { return std::uniform_int_distribution<int>(lo, hi)(rng); };
   auto chance = [&](int pct) { return I(1, 100) <= pct; };
   for(int b = 0; b < kBrokerCount; b++)
      for(int j = 0; j < kSymCount; j++)
        {
         const BrokerProfile &pr = kBrokers[b];
         SetUpBridge(std::string("changes: ") + pr.name + ", " + kSyms[j].name, &pr, &kSyms[j]);
         AiSettings cfg = Cfg();
         cfg.maxRiskPct = 0.0;
         s_b.Init(cfg);
         s_b.Start();
         Drain();
         const double pt = g_fake.sym.point;
         const double tick = g_fake.sym.tickSize;
         const double spread = g_fake.sym.ask - g_fake.sym.bid;
         const double mid0 = g_fake.sym.bid;
         const int stops = std::max(g_fake.sym.stops, 1);
         auto grid = [&](double v) { return NormalizeDouble(std::round(v / tick) * tick, g_fake.sym.digits); };
         auto lots = [&]() { return NormalizeDouble(g_fake.sym.volMin + I(0, 4) * g_fake.sym.volStep, 8); };
         for(int r = 0; r < rounds; r++)
           {
            g_fake.pos.clear();
            g_fake.ords.clear();
            g_fake.refusals.clear();
            g_fake.sym.bid = grid(mid0 + I(-300, 300) * pt);
            g_fake.sym.ask = grid(g_fake.sym.bid + spread);
            const double bid = g_fake.sym.bid;
            const double ask = g_fake.sym.ask;

            // A position, in profit or at a loss, with levels the server took.
            bool posBuy = chance(50);
            double posPx = posBuy ? bid : ask;   // where it closes
            double dirSl = posBuy ? -1.0 : 1.0;
            AddPos(501, posBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, lots(), grid((posBuy ? ask : bid) + I(-300, 300) * pt),
                   grid(posPx + dirSl * I(stops + 5, stops + 400) * pt), grid(posPx - dirSl * I(stops + 5, stops + 400) * pt), 1000);

            // A pending order of any of the four types, with an expiry the symbol may no longer take.
            static const int kTypes[4] = {ORDER_TYPE_BUY_LIMIT, ORDER_TYPE_BUY_STOP, ORDER_TYPE_SELL_LIMIT, ORDER_TYPE_SELL_STOP};
            int ot = kTypes[I(0, 3)];
            bool ordBuy = BuyType(ot);
            bool below = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_STOP);
            double oprice = grid((ordBuy ? ask : bid) + (below ? -1.0 : 1.0) * I(stops + 5, stops + 400) * pt);
            double odir = ordBuy ? 1.0 : -1.0;
            int tt = I(0, 3);
            datetime exp = (tt == ORDER_TIME_SPECIFIED || tt == ORDER_TIME_SPECIFIED_DAY) ? g_fake.time + I(-3600, 3 * 86400) : 0;
            g_fake.ords.push_back(FakeOrd{502, ot, lots(), oprice, grid(oprice - odir * I(stops + 5, stops + 300) * pt),
                                          grid(oprice + odir * I(stops + 5, stops + 300) * pt), 0.0, tt, exp, g_fake.sym.name,
                                          (ulong)I(0, 9), chance(50) ? "manual" : ""});

            for(int k = 0; k < 12; k++)
              {
               bool onOrder = (k % 2 == 1);
               if(onOrder && g_fake.ords.empty())
                  continue;
               st.changes++;
               std::string fields;
               std::string what;
               double wasOpen, wasSl, wasTp;
               int wasType = 0;
               ulong ticket;
               bool buy;
               // A level for the change: break-even, at or just inside the stops level, across the
               // price, around the entry, unchanged, none, off the grid, or anywhere on its side.
               auto level = [&](double was, double from, double dir, double entry) {
                  double v;
                  switch(I(0, 9))
                    {
                     case 0:
                     case 1: v = entry; break;
                     case 2: v = grid(from + dir * stops * pt); break;
                     case 3: v = grid(from + dir * (stops - 1) * pt); break;
                     case 4: v = grid(from - dir * I(0, 50) * pt); break;
                     case 5: v = grid(entry + dir * I(-50, 50) * pt); break;
                     case 6: v = was; break;
                     default: v = grid(from + dir * I(1, 500) * pt); break;
                    }
                  if(chance(4))
                     v = 0.0;
                  else if(chance(8))
                     v += tick * 0.4;
                  return v;
               };
               if(!onOrder)
                 {
                  const FakePos &p = g_fake.pos[0];
                  buy = (p.type == POSITION_TYPE_BUY);
                  ticket = p.ticket;
                  wasOpen = p.open;
                  wasSl = p.sl;
                  wasTp = p.tp;
                  double px = buy ? bid : ask;
                  double dir = buy ? -1.0 : 1.0;
                  double sl = level(p.sl, px, dir, p.open);
                  double tp = level(p.tp, px, -dir, p.open);
                  fields = Field("ticket", (double)ticket) + "," + Field("sl", sl) + "," + Field("tp", tp);
                  what = std::string(buy ? "buy" : "sell") + " position open " + Px(p.open) + ", SL " + Px(p.sl) + " -> " + Px(sl) + ", TP " +
                         Px(p.tp) + " -> " + Px(tp);
                 }
               else
                 {
                  const FakeOrd &o = g_fake.ords[0];
                  buy = BuyType(o.type);
                  ticket = o.ticket;
                  wasType = o.type;
                  wasOpen = o.price;
                  wasSl = o.sl;
                  wasTp = o.tp;
                  double ref = buy ? ask : bid;
                  double open;
                  switch(I(0, 9))
                    {
                     case 0:
                     case 1:
                     case 2: open = grid(ref + (chance(50) ? 1.0 : -1.0) * I(stops, stops + 300) * pt); break;   // either side: may cross
                     case 3: open = ref; break;                                                                  // at the market
                     case 4: open = grid(ref + (chance(50) ? 1.0 : -1.0) * (stops - 1) * pt); break;            // inside the stops level
                     case 5: open = o.price; break;
                     default: open = grid(o.price + I(-200, 200) * pt); break;
                    }
                  double d = open - o.price;
                  double dir = buy ? -1.0 : 1.0;
                  double sl = chance(70) ? grid(o.sl + d) : level(o.sl, open, dir, open);
                  double tp = chance(70) ? grid(o.tp + d) : level(o.tp, open, -dir, open);
                  fields = Field("ticket", (double)ticket) + "," + Field("open", open) + "," + Field("sl", sl) + "," + Field("tp", tp);
                  what = AiOrderTypeName((ENUM_ORDER_TYPE)o.type).s + " at " + Px(o.price) + " -> " + Px(open) + ", SL " + Px(o.sl) + " -> " +
                         Px(sl) + ", TP " + Px(o.tp) + " -> " + Px(tp);
                 }
               what += ", bid " + Px(bid) + " ask " + Px(ask) + ", stops " + std::to_string(g_fake.sym.stops) + " freeze " +
                       std::to_string(g_fake.sym.freeze) + ": ";

               JV m = Req("modPreview", fields);
               const JV &md = m["mod"];
               double nOpen = onOrder ? md["open"].n : wasOpen;
               double nSl = md["sl"].n;
               double nTp = md["tp"].n;
               double eps = pt * 0.5;
               bool changed = std::fabs(nOpen - wasOpen) > eps || std::fabs(nSl - wasSl) > eps || std::fabs(nTp - wasTp) > eps;

               // What the server takes, worked out from its own rules.
               int newType = wasType;
               bool serverOk = changed && nSl > 0.0 && nTp > 0.0 && g_fake.sym.tradeMode != SYMBOL_TRADE_MODE_DISABLED;
               if(serverOk && !onOrder)
                  serverOk = !FakeFrozen(wasSl, buy) && !FakeFrozen(wasTp, buy) && FakeCheckLevels(buy, 0.0, nSl, nTp) == 0;
               else if(serverOk)
                 {
                  double ref = buy ? ask : bid;
                  if(std::fabs(nOpen - ref) < eps)
                     serverOk = false;   // no type at the market price
                  else
                     newType = buy ? (nOpen < ref ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP) : (nOpen > ref ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP);
                  if(serverOk && FakeFrozen(wasOpen, !buy))
                     serverOk = false;
                  if(serverOk && newType != wasType)
                    {
                     // A new order of the other type: the symbol must take it.
                     bool limit = (newType == ORDER_TYPE_BUY_LIMIT || newType == ORDER_TYPE_SELL_LIMIT);
                     int tm = g_fake.sym.tradeMode;
                     if(g_fake.sym.orderMode != 0 && !(g_fake.sym.orderMode & (limit ? SYMBOL_ORDER_LIMIT : SYMBOL_ORDER_STOP)))
                        serverOk = false;
                     if(tm == SYMBOL_TRADE_MODE_CLOSEONLY || (tm == SYMBOL_TRADE_MODE_LONGONLY && !buy) || (tm == SYMBOL_TRADE_MODE_SHORTONLY && buy))
                        serverOk = false;
                    }
                  if(serverOk)
                     serverOk = FakeCheckPendingPrice(newType, nOpen) == 0 && FakeCheckLevels(buy, nOpen, nSl, nTp) == 0;
                 }

               bool eaOk = m["ok"].b && md["valid"].b;
               if(!onOrder && std::fabs(nSl - wasOpen) < eps)
                 {
                  if(eaOk)
                     st.breakEven++;
                  else if(Has(md["err"].s, "Break-even needs"))
                     st.breakEvenRefused++;
                 }
               if(eaOk)
                 {
                  st.allowed++;
                  if(onOrder && newType != wasType)
                     st.retyped++;
                 }
               EXPECT(m["ok"].b, what + "the preview is answered: " + m["err"].s);
               if(eaOk != serverOk)
                  EXPECT(false, what + (eaOk ? "the preview allows a change the server refuses" : "the preview refuses a change the server takes: \"" +
                                                   md["err"].s + "\""));
               else
                  EXPECT(true, "");
               if(eaOk && onOrder)
                  EXPECT(md["retype"].b == (newType != wasType), what + "the preview says whether the order changes type");

               size_t sentBefore = g_fake.requests.size();
               JV s = Req("modSend", Quoted("preview", m["preview"].s));
               if(!eaOk)
                 {
                  EXPECT(!s["ok"].b && g_fake.requests.size() == sentBefore, what + "a refused change sends nothing");
                  continue;
                 }
               EXPECT(s["ok"].b, what + "an allowed change goes through: " + s["err"].s);
               EXPECT(g_fake.refusals.empty(), what + "the server refused nothing");
               g_fake.refusals.clear();
               if(!s["ok"].b)
                  continue;
               if(!onOrder)
                 {
                  const FakePos &p = g_fake.pos[0];
                  EXPECT(Near(p.sl, nSl, eps) && Near(p.tp, nTp, eps), what + "the server has the previewed SL and TP");
                 }
               else if(newType == wasType)
                 {
                  EXPECT(g_fake.ords.size() == 1 && g_fake.ords[0].ticket == ticket && Near(g_fake.ords[0].price, nOpen, eps) &&
                         Near(g_fake.ords[0].sl, nSl, eps) && Near(g_fake.ords[0].tp, nTp, eps), what + "the order is changed as previewed");
                 }
               else
                 {
                  const FakeOrd *o = g_fake.ords.empty() ? nullptr : &g_fake.ords[0];
                  EXPECT(g_fake.ords.size() == 1 && o->ticket != ticket && o->type == newType && Near(o->price, nOpen, eps) && Near(o->sl, nSl, eps) &&
                         Near(o->tp, nTp, eps), what + "the order is replaced by one of the other type, as previewed");
                  EXPECT(o && (ulong)s["ticket"].n == o->ticket && s["replaced"].b, what + "the reply names the new order");
                 }
              }
           }
        }
  }

//--- a confirm sends what its preview showed --------------------------------------------------
static void TestPreviewHolds()
  {
   SetUpBridge("a confirm sends what its preview showed");
   s_b.Start();
   Drain();
   // A BUY LIMIT below the market; the ask then falls under its entry: now it would be a BUY STOP.
   JV p = Req("preview", PreviewFields("EURUSD", "buy", true, 1.08300));
   EXPECT(p["ok"].b && p["plan"]["type"].s == "BUY LIMIT", "a pending BUY under the market is a BUY LIMIT");
   g_fake.sym.bid = 1.08230;
   g_fake.sym.ask = 1.08250;
   JV s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "BUY STOP") && g_fake.requests.empty(), "the price crossed its entry: refused, not sent as a BUY STOP: " + s["err"].s);
   g_fake.sym.bid = 1.08480;
   g_fake.sym.ask = 1.08500;

   // 1% with an SL set as a price: the market moves away from the stop, the same risk needs fewer lots.
   p = Req("preview", PreviewFields("EURUSD", "buy", false, 0.0, "price", 1.08300, "r", 2.0, "percent", 1.0));
   EXPECT(p["ok"].b && Near(p["plan"]["lots"].n, 0.50), "1% with a 20-pip stop: 0.50 lots");
   g_fake.sym.bid += 0.00020;
   g_fake.sym.ask += 0.00020;
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "lots changed") && g_fake.requests.empty(), "the lots would differ from the preview's: refused: " + s["err"].s);
   g_fake.sym.bid -= 0.00020;
   g_fake.sym.ask -= 0.00020;

   // The same login on another broker's server.
   p = Req("preview", PreviewFields("EURUSD", "buy"));
   g_fake.server = "OtherBroker-Live";
   s = Req("send", Quoted("preview", p["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "another account") && g_fake.requests.empty(), "the same login on another server is another account");
   g_fake.server = "FakeServer";

   // A change previewed on a pending order, then the price crosses the new entry before the confirm.
   g_fake.ords.push_back(FakeOrd{311, ORDER_TYPE_BUY_LIMIT, 0.10, 1.08300, 1.08100, 1.08700, 0.0, ORDER_TIME_GTC, 0, g_fake.sym.name});
   JV m = Req("modPreview", Field("ticket", 311) + "," + Field("open", 1.08350) + "," + Field("sl", 1.08150) + "," + Field("tp", 1.08750));
   EXPECT(m["ok"].b && m["mod"]["valid"].b && !m["mod"]["retype"].b, "a BUY LIMIT moved up, still under the market");
   g_fake.sym.bid = 1.08310;
   g_fake.sym.ask = 1.08330;
   s = Req("modSend", Quoted("preview", m["preview"].s));
   EXPECT(!s["ok"].b && Has(s["err"].s, "BUY STOP") && g_fake.requests.empty() && g_fake.ords.size() == 1 && g_fake.ords[0].ticket == 311,
          "the market crossed the new entry: refused, the order is not replaced: " + s["err"].s);
   g_fake.sym.bid = 1.08480;
   g_fake.sym.ask = 1.08500;
   ServerRefusedNothing();
  }

//--- the preview gate, fuzzed -------------------------------------------------------------
// Requests in random order, as a panel gone wrong or a forged link would send them: previews of
// every kind; confirms naming real, reused, expired, evicted, forged, look-alike and other-kind
// previews; previews made on another account or server; junk frames; the clock jumping and the
// panel reconnecting. Whatever comes, the server gets a request only from a confirm naming a preview
// of its own kind, made on this login and server within the last minute, among the newest 32 since
// the panel connected and never confirmed before; or from removing a pending order that is there.
struct GateStats { int steps = 0, confirms = 0, sent = 0, refused = 0, forged = 0, cancels = 0, junk = 0; };

static const char kNulFrame[] = "{\"t\":\"send\",\"id\":5,\"preview\":\"p1\0\"}";   // a NUL inside the id

static std::string JsonText(const std::string &s)
  {
   std::string o = "\"";
   for(unsigned char c : s)
     {
      if(c == '"' || c == '\\')
        {
         o += '\\';
         o += (char)c;
        }
      else if(c < 0x20)
        {
         char b[8];
         snprintf(b, sizeof b, "\\u%04x", c);
         o += b;
        }
      else
         o += (char)c;
     }
   return o + "\"";
  }

static void FuzzPreviewGate(std::mt19937 &rng, int steps, GateStats &st)
  {
   auto I = [&](int lo, int hi) { return std::uniform_int_distribution<int>(lo, hi)(rng); };
   SetUpBridge("the preview gate, fuzzed");
   s_b.Start();
   Drain();
   struct Pv { std::string id, kind; ulong madeMs; int64_t login; std::string server; bool used; size_t session; };
   std::vector<Pv> pvs;
   size_t session = 0;
   size_t sessionStart = 0;
   const double mid0 = g_fake.sym.bid;
   const char *kinds[] = { "send", "modSend", "close" };
   for(int n = 0; n < steps; n++, st.steps++)
     {
      if(g_fake.pos.empty())
         AddPos(g_fake.nextTicket++, I(0, 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, 0.10 * I(1, 5), mid0 + I(-50, 50) * 0.00001, 0.0, 0.0, 1);
      if(g_fake.ords.empty())
         g_fake.ords.push_back(FakeOrd{g_fake.nextTicket++, ORDER_TYPE_BUY_LIMIT, 0.10, mid0 - 0.00300, mid0 - 0.00500, mid0 + 0.00100, 0.0, ORDER_TIME_GTC, 0,
                                       g_fake.sym.name});
      // the market drifts
      double drift = I(-3, 3) * 0.00001;
      g_fake.sym.bid = NormalizeDouble(std::min(std::max(g_fake.sym.bid + drift, mid0 - 0.00400), mid0 + 0.00400), 5);
      g_fake.sym.ask = NormalizeDouble(g_fake.sym.bid + 0.00020, 5);
      auto ticket = [&]() -> long
        {
         int w = I(0, 9);
         if(w < 4 && !g_fake.pos.empty())
            return (long)g_fake.pos[I(0, (int)g_fake.pos.size() - 1)].ticket;
         if(w < 8 && !g_fake.ords.empty())
            return (long)g_fake.ords[I(0, (int)g_fake.ords.size() - 1)].ticket;
         return (long)I(-5, 1000000000);
        };
      auto px = [&](int pips) { return Px(NormalizeDouble(g_fake.sym.bid + pips * 0.0001, 5)); };
      size_t before = g_fake.requests.size();
      int a = I(0, 99);
      if(a < 16)
        {
         std::string slMode = (I(0, 3) == 0) ? "price" : "pips";
         double sl = (slMode == "price") ? g_fake.sym.bid - I(-10, 40) * 0.0001 : I(0, 40);
         JV r = Req("preview", PreviewFields(I(0, 9) ? "EURUSD" : "NOPE", I(0, 1) ? "buy" : "sell", I(0, 2) == 0, g_fake.sym.bid + I(-30, 30) * 0.0001, slMode, sl,
                                             I(0, 1) ? "r" : "pips", I(0, 40) * 0.1, I(0, 3) ? "percent" : "lots", I(1, 30) * 0.1));
         if(r["ok"].b)
            pvs.push_back(Pv{r["preview"].s, "send", AiNowMs(), g_fake.login, g_fake.server, false, session});
        }
      else if(a < 26)
        {
         JV r = Req("modPreview", Field("ticket", (double)ticket()) + (I(0, 3) ? "," + std::string("\"open\":") + px(I(-40, 40)) : "") + ",\"sl\":" + px(I(-40, 40)) +
                    ",\"tp\":" + px(I(-40, 40)));
         if(r["ok"].b)
            pvs.push_back(Pv{r["preview"].s, "modSend", AiNowMs(), g_fake.login, g_fake.server, false, session});
        }
      else if(a < 33)
        {
         JV r = Req("closePreview", Field("ticket", (double)ticket()) + (I(0, 2) ? "," + Field("lots", I(0, 6) * 0.05) : ""));
         if(r["ok"].b)
            pvs.push_back(Pv{r["preview"].s, "close", AiNowMs(), g_fake.login, g_fake.server, false, session});
        }
      else if(a < 70)
        {
         st.confirms++;
         std::string type = kinds[I(0, 2)];
         std::string json;        // what the confirm names, as JSON
         std::string named;       // the id that is, when it names one exactly
         int how = I(0, 19);
         if(how < 12 && !pvs.empty())
           {
            named = pvs[I(std::max(0, (int)pvs.size() - 40), (int)pvs.size() - 1)].id;
            json = JsonText(named);
           }
         else
           {
            st.forged++;
            std::string real = pvs.empty() ? "p1" : pvs[I(0, (int)pvs.size() - 1)].id;
            std::string up = real;
            up[0] = 'P';
            const std::string forged[] = { "\"\"", "\"p0\"", "\"p-1\"", JsonText(up), JsonText(" " + real), JsonText(real + " "), JsonText("p0" + real.substr(1)),
                                           JsonText(real + "x"), "\"p" + std::to_string(I(1, 2000000000)) + "9\"", "1", "true", "null", "[" + JsonText(real) + "]",
                                           "{\"id\":" + JsonText(real) + "}", JsonText(real.substr(0, real.size() - 1)), "-0", "1e9" };
            json = forged[I(0, (int)(sizeof(forged) / sizeof(forged[0])) - 1)];
            if(json.size() > 2 && json[0] == '"' && json.find('\\') == std::string::npos)
               named = json.substr(1, json.size() - 2);
            if(I(0, 4) == 0 && !pvs.empty())
              {
               // The real id written with escapes: the same string, so it counts as naming it.
               named = pvs[I(0, (int)pvs.size() - 1)].id;
               json = "\"";
               for(char c : named)
                 {
                  char b[8];
                  snprintf(b, sizeof b, "\\u%04x", (unsigned char)c);
                  json += b;
                 }
               json += "\"";
              }
           }
         // What the bridge may do: find the preview the confirm names, exactly.
         bool legit = false;
         for(size_t i = 0; i < pvs.size(); i++)
           {
            Pv &v = pvs[i];
            bool alive = v.session == session && i >= sessionStart && pvs.size() - i <= AI_PREVIEW_MAX;
            if(v.id != named || !alive || v.kind != type)
               continue;
            legit = !v.used && AiNowMs() - v.madeMs <= AI_PREVIEW_TTL_MS && v.login == g_fake.login && v.server == g_fake.server;
            v.used = true;
            break;
           }
         JV r = Req(type, "\"preview\":" + json);
         size_t made = g_fake.requests.size() - before;
         EXPECT(made == 0 || legit, "a server request only from a confirm of a usable preview: " + type + " " + json + " (" + r["err"].s + ")");
         EXPECT(!r["ok"].b || legit, "a confirm says it went through only for a usable preview: " + type + " " + json);
         EXPECT(made <= 4, "one confirm makes at most a few server requests (retries, SL/TP after a slipped fill, replacing an order)");
         if(r["ok"].b)
            st.sent++;
         else
            st.refused++;
        }
      else if(a < 76)
        {
         st.cancels++;
         long t = ticket();
         bool pending = false;
         for(auto &o : g_fake.ords)
            pending = pending || (long)o.ticket == t;
         JV r = Req("cancel", Field("ticket", (double)t));
         EXPECT(g_fake.requests.size() == before || pending, "a removal only of a pending order that is there: #" + std::to_string(t));
         EXPECT(g_fake.requests.size() - before <= 1 && (!r["ok"].b || pending), "and only that one");
        }
      else if(a < 82)
         Advance(I(0, 3) == 0 ? I(30000, 70000) : I(0, 2000));
      else if(a < 85)
         g_fake.login = (g_fake.login == 12345678) ? 87654321 : 12345678;
      else if(a < 88)
         g_fake.server = (g_fake.server == "FakeServer") ? "FakeServer-2" : "FakeServer";
      else if(a < 90)
        {
         // the panel reconnects: the previews it had are gone
         s_b.Start();
         Drain();
         session++;
         sessionStart = pvs.size();
        }
      else if(a < 95)
        {
         st.junk++;
         const std::string junk[] = { "", "{", "}", "[]", "null", "{\"t\":\"send\"}", "{\"t\":\"send\",\"id\":0,\"preview\":\"p1\"}",
                                      "{\"t\":\"send\",\"id\":-4,\"preview\":\"p1\"}", "{\"t\":\"send\",\"id\":\"x\",\"preview\":\"p1\"}",
                                      "{\"t\":\"send\",\"id\":7,\"preview\":\"p1\"} trailing", "{\"t\":\"send\" \"id\":7}", "{\"t\":\"send\",\"id\":7,\"preview\":\"p1\"",
                                      "{'t':'send','id':7,'preview':'p1'}", "{\"t\":\"se\\u006ed\",\"id\":1e400}", "{\"t\":[\"send\"],\"id\":5}",
                                      "\xff\xfe{\"t\":\"send\"}", std::string(kNulFrame, sizeof kNulFrame - 1) };
         std::string j = junk[I(0, (int)(sizeof(junk) / sizeof(junk[0])) - 1)];
         if(I(0, 3) == 0)
           {
            j.clear();
            for(int k = I(0, 60); k > 0; k--)
               j += (char)I(1, 255);
           }
         s_b.Handle(string(j));
         std::vector<JV> got = Drain();
         // A frame that names a preview sends nothing unless the oracle allows that very preview;
         // these name "p1" at most, so the server must not have moved unless p1 is usable.
         bool p1Usable = false;
         for(size_t i = 0; i < pvs.size(); i++)
            if(pvs[i].id == "p1" && pvs[i].session == session && i >= sessionStart && !pvs[i].used && pvs[i].kind == "send" &&
               AiNowMs() - pvs[i].madeMs <= AI_PREVIEW_TTL_MS && pvs[i].login == g_fake.login && pvs[i].server == g_fake.server)
               p1Usable = true;
         EXPECT(g_fake.requests.size() == before || p1Usable, "a junk frame moves nothing on the server: " + j.substr(0, 60));
         for(size_t i = 0; i < pvs.size(); i++)
            if(pvs[i].id == "p1" && g_fake.requests.size() != before)
               pvs[i].used = true;
        }
      else
        {
         const char *other[] = { "symbols", "watch", "recall", "pick", "fly", "link.start", "" };
         Req(other[I(0, 6)], Quoted("symbol", I(0, 1) ? "EURUSD" : "X") + "," + Quoted("ticker", "FX:EURUSD") + "," + Quoted("side", "buy"));
         EXPECT(g_fake.requests.size() == before, "a request that is not a confirm moves nothing on the server");
        }
     }
   EXPECT(st.sent > 0 && st.refused > 0 && st.forged > 0, "the fuzz both sent and refused orders (" + std::to_string(st.sent) + " sent, " +
          std::to_string(st.refused) + " refused)");
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

//--- the link's key, fuzzed ---------------------------------------------------------------
// The first frame on the pipe in many shapes: the key exactly, reordered, escaped, padded with
// whitespace, split across reads; and near misses: a character off, cut short, longer, upper case,
// with a space, under another name, nested, as another type, after a wrong frame, in broken JSON,
// and a good frame with one byte changed. The EA serves only when its first frame's "t" is "link" and
// its "key" is the key, exactly.
struct KeyStats { int rounds = 0, served = 0, refused = 0; };

static void FuzzLinkKey(std::mt19937 &rng, int rounds, KeyStats &st)
  {
   auto I = [&](int lo, int hi) { return std::uniform_int_distribution<int>(lo, hi)(rng); };
   const std::string K = kKey;
   const std::string good = "{\"t\":\"link\",\"key\":\"" + K + "\"}";
   for(int n = 0; n < rounds; n++, st.rounds++)
     {
      s_case = "the link's key, fuzzed";
      g_fake.Reset();
      _Symbol = string(g_fake.sym.name);
      SetKeyFile(kKey);
      g_fake.pipe.serving = true;
      std::string off = K;
      off[I(0, 31)] = "0123456789abcdef"[I(0, 15)];
      std::string upper = K;
      for(char &c : upper)
         c = (char)toupper((unsigned char)c);
      std::string escaped;
      for(char c : K)
        {
         char b[8];
         snprintf(b, sizeof b, "\\u%04x", (unsigned char)c);
         escaped += b;
        }
      std::string first;
      bool want = false;
      bool split = false;
      int v = I(0, 31);
      switch(v)
        {
         case 0: first = good; want = true; break;
         case 1: first = "{\"key\":\"" + K + "\",\"t\":\"link\"}"; want = true; break;
         case 2: first = " {\n\t\"t\" : \"link\" ,\r\n \"key\" : \"" + K + "\" , \"x\":[1,{\"y\":2}] } "; want = true; break;
         case 3: first = "{\"t\":\"link\",\"key\":\"" + escaped + "\"}"; want = true; break;
         case 4: first = "{\"t\":\"link\",\"key\":\"wrong\",\"key\":\"" + K + "\"}"; want = true; break;   // the last of a repeated key counts
         case 5: first = good; want = true; split = true; break;
         case 6: first = "{\"t\":\"link\",\"key\":\"" + off + "\"}"; want = (off == K); break;
         case 7: first = "{\"t\":\"link\",\"key\":\"" + K.substr(0, I(0, 31)) + "\"}"; break;
         case 8: first = "{\"t\":\"link\",\"key\":\"" + K + "0\"}"; break;
         case 9: first = "{\"t\":\"link\",\"key\":\"" + upper + "\"}"; break;
         case 10: first = "{\"t\":\"link\",\"key\":\" " + K + "\"}"; break;
         case 11: first = "{\"t\":\"link\",\"key\":\"" + K + " \"}"; break;
         case 12: first = "{\"t\":\"Link\",\"key\":\"" + K + "\"}"; break;
         case 13: first = "{\"t\":\"link \",\"key\":\"" + K + "\"}"; break;
         case 14: first = "{\"key\":\"" + K + "\"}"; break;
         case 15: first = "{\"t\":\"link\",\"Key\":\"" + K + "\"}"; break;
         case 16: first = "{\"t\":\"link\",\"key\":[\"" + K + "\"]}"; break;
         case 17: first = "{\"t\":\"link\",\"link\":{\"key\":\"" + K + "\"}}"; break;
         case 18: first = "{\"t\":\"link\",\"key\":\"" + K + "\",\"key\":\"wrong\"}"; break;
         case 19: first = good + " x"; break;
         case 20: first = good.substr(0, good.size() - 1); break;
         case 21: first = "[" + good + "]"; break;
         case 22: first = ""; break;
         case 23: first = "{\"t\":\"link\",\"key\":null}"; break;
         case 24: first = "{\"t\":\"link\",\"key\":true}"; break;
         case 25: first = "{\"t\":\"link\",\"key\":\"\"}"; break;
         case 26: first = "{\"t\":\"watch\",\"id\":1,\"symbol\":\"EURUSD\",\"key\":\"" + K + "\"}"; break;
         default:
           {
            // In this compact frame any changed byte breaks the JSON, the "t" or the key.
            first = good;
            int at = I(0, (int)first.size() - 1);
            char was = first[at];
            first[at] = (char)I(1, 255);
            want = (first[at] == was);
            break;
           }
        }
      CAiLink link;
      link.Init(Cfg(), true);
      bool wrongFirst = false;
      if(I(0, 5) == 0)
        {
         std::string k = I(0, 1) ? off : std::string("x");
         PushFrame("{\"t\":\"link\",\"key\":\"" + k + "\"}");
         wrongFirst = (k != K);
         want = want || !wrongFirst;   // a right key first: served whatever follows
        }
      std::string rest;
      if(split)
        {
         uint32_t len = (uint32_t)first.size();
         for(int i = 0; i < 4; i++)
            g_fake.pipe.toEa += (char)((len >> (8 * i)) & 0xFF);
         g_fake.pipe.toEa += first.substr(0, 10);
         rest = first.substr(10);
        }
      else
        {
         PushFrame(first);
         PushFrame("{\"t\":\"watch\",\"id\":1,\"symbol\":\"EURUSD\"}");
        }
      link.Timer();
      if(split)
        {
         // the rest of the key frame arrives on a later read
         g_fake.pipe.toEa += rest;
         PushFrame("{\"t\":\"watch\",\"id\":1,\"symbol\":\"EURUSD\"}");
        }
      for(int k = 0; k < 3; k++)
        {
         Advance(25);
         link.Timer();
        }
      bool served = !g_fake.pipe.fromEa.empty();
      bool expect = want && !wrongFirst;
      EXPECT(served == expect, std::string(expect ? "served: " : "refused: ") + "case " + std::to_string(v) + ": " + first.substr(0, 90));
      if(served)
         st.served++;
      else
         st.refused++;
      link.Deinit();
     }
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
   TestPreviewHolds();
   int bridgeChecks = s_pass + s_fail - jsonChecks;
   int bridgeFails = s_fail - jsonFails;
   printf("bridge: %d checks over %d broker profiles, %d failed\n", bridgeChecks, kBrokerCount, bridgeFails);

   int rounds = (argc > 3) ? atoi(argv[3]) : 60;
   ChangeStats st;
   FuzzChanges(rng, rounds, st);
   int changeChecks = s_pass + s_fail - jsonChecks - bridgeChecks;
   int changeFails = s_fail - jsonFails - bridgeFails;
   printf("changes: %d checks over %d changes (%d broker profiles x %d symbols x %d rounds, seed %u), %d failed\n", changeChecks, st.changes,
          kBrokerCount, kSymCount, rounds, seed, changeFails);
   printf("changes: %d allowed and sent, of which %d turned a pending order into the other type and %d set break-even; "
          "%d break-evens refused as too early\n", st.allowed, st.retyped, st.breakEven, st.breakEvenRefused);

   int gateSteps = (argc > 4) ? atoi(argv[4]) : 100000;
   GateStats gs;
   int before = s_pass + s_fail;
   int failsBefore = s_fail;
   FuzzPreviewGate(rng, gateSteps, gs);
   printf("preview gate: %d checks over %d requests (%d confirms: %d sent, %d refused, %d forged; %d removals; %d junk frames), %d failed\n",
          s_pass + s_fail - before, gs.steps, gs.confirms, gs.sent, gs.refused, gs.forged, gs.cancels, gs.junk, s_fail - failsBefore);

   before = s_pass + s_fail;
   failsBefore = s_fail;
   TestHostElection();
   TestLinkKey();
   TestLinkEndToEnd();
   KeyStats ks;
   FuzzLinkKey(rng, (argc > 5) ? atoi(argv[5]) : 20000, ks);
   printf("link: %d checks (%d first frames fuzzed: %d served, %d refused), %d failed\n", s_pass + s_fail - before, ks.rounds, ks.served, ks.refused,
          s_fail - failsBefore);
   return s_fail ? 1 : 0;
  }
