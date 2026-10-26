//+------------------------------------------------------------------+
//| ActionInna - the browser panel's requests, answered in MT5       |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_BRIDGE_MQH
#define ACTIONINNA_BRIDGE_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "SymbolSpec.mqh"
#include "RiskCalc.mqh"
#include "Memory.mqh"
#include "Trades.mqh"
#include "Executor.mqh"
#include "Json.mqh"
#include "SymbolMap.mqh"

// Reads the browser panel's requests, answers them, and queues what MT5 tells the panel by itself:
// the terminal's state, quotes and trades. The protocol is in docs/protocol.md. This class knows
// nothing about the pipe, so the tests drive it directly. Every number and every rule is the chart
// panel's own: AiBuildPlan, AiBuildModPlan, AiCheckClose, CAiExecutor, AiAfterFill.

#define AI_BRIDGE_VER      1
#define AI_PREVIEW_TTL_MS  60000
#define AI_PREVIEW_MAX     32
#define AI_PV_NEW          0
#define AI_PV_MOD          1
#define AI_PV_CLOSE        2

// A preview the panel may confirm once, within AI_PREVIEW_TTL_MS, on the same account. What is sent
// must be what it showed: the same order type (a new order, or a change that replaces a pending
// order) and the same lots.
struct AiPreview
  {
   string            id;
   int               kind;
   ulong             madeMs;
   long              login;
   string            server;
   bool              used;
   string            symbol;
   ENUM_ORDER_TYPE   type;
   AiInput           in;           // a new order
   double            seenRisk;
   double            seenLots;
   ulong             ticket;       // a change or a close
   double            open;         // the change asked for
   double            sl;
   double            tp;
   double            lots;         // the lots to close
   double            wasOpen;      // the trade as it was at the preview
   double            wasSl;
   double            wasTp;
   double            wasLots;
  };

//--- words the protocol uses --------------------------------------------

string AiWordMarginMode()
  {
   long m = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(m == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "hedging";
   return (m == ACCOUNT_MARGIN_MODE_EXCHANGE) ? "exchange" : "netting";
  }

string AiWordAccountMode()
  {
   long m = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(m == ACCOUNT_TRADE_MODE_REAL)
      return "real";
   return (m == ACCOUNT_TRADE_MODE_CONTEST) ? "contest" : "demo";
  }

string AiWordExecution(const int exeMode)
  {
   if(exeMode == SYMBOL_TRADE_EXECUTION_REQUEST)
      return "request";
   if(exeMode == SYMBOL_TRADE_EXECUTION_INSTANT)
      return "instant";
   if(exeMode == SYMBOL_TRADE_EXECUTION_EXCHANGE)
      return "exchange";
   return "market";
  }

string AiWordSymbolMode(const int tradeMode)
  {
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      return "disabled";
   if(tradeMode == SYMBOL_TRADE_MODE_LONGONLY)
      return "longOnly";
   if(tradeMode == SYMBOL_TRADE_MODE_SHORTONLY)
      return "shortOnly";
   if(tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return "closeOnly";
   return "full";
  }

string AiWordLevelMode(const int mode)
  {
   if(mode == AI_LEVEL_PRICE)
      return "price";
   return (mode == AI_LEVEL_RR) ? "r" : "pips";
  }

string AiWordPipMode(const int mode)
  {
   if(mode == AI_PIP_EXNESS)
      return "10points";
   return (mode == AI_PIP_POINT) ? "points" : "trader";
  }

string AiWordSlip(const int policy)
  {
   if(policy == AI_SLIP_KEEP_PRICES)
      return "keepPrices";
   return (policy == AI_SLIP_KEEP_RISK) ? "keepRisk" : "follow";
  }

int AiParseSide(const string s)
  {
   if(s == "buy")
      return AI_BUY;
   return (s == "sell") ? AI_SELL : 0;
  }

// -1 when the word is not a level mode (R only for a take profit).
int AiParseLevelMode(const string s, const bool allowR)
  {
   if(s == "pips")
      return AI_LEVEL_PIPS;
   if(s == "price")
      return AI_LEVEL_PRICE;
   return (s == "r" && allowR) ? AI_LEVEL_RR : -1;
  }

int AiParseRiskMode(const string s)
  {
   if(s == "percent")
      return AI_RISK_PERCENT;
   if(s == "money")
      return AI_RISK_MONEY;
   return (s == "lots") ? AI_RISK_LOTS : -1;
  }

// Decimals to write a symbol's prices with; -1 (up to 8, trimmed) for a symbol MT5 doesn't know.
int AiPriceDigits(const string symbol)
  {
   if(SymbolInfoDouble(symbol, SYMBOL_POINT) <= 0.0)
      return -1;
   return (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  }

class CAiBridge
  {
private:
   AiSettings        m_cfg;
   CAiExecutor       m_exec;
   CAiSymbolMap      m_map;
   string            m_out[];
   AiPreview         m_pv[];
   int               m_pvSeq;
   string            m_watch;
   AiSpec            m_watchSpec;
   double            m_lastBid;
   double            m_lastAsk;
   ulong             m_lastQuoteMs;
   string            m_lastTerminal;
   ulong             m_lastTerminalMs;
   string            m_lastTradesSig;
   ulong             m_lastTradesCheckMs;
   ulong             m_lastTradesSentMs;
   bool              m_tradeEvent;

   void              Queue(const string json)
     {
      int n = ArraySize(m_out);
      ArrayResize(m_out, n + 1, 16);
      m_out[n] = json;
     }

   void              Begin(CAiJsonOut &o, const long id) const
     {
      o.Str("t", "reply");
      o.Int("id", id);
      o.Bool("ok", true);
     }

   void              Ok(const long id)
     {
      CAiJsonOut o;
      Begin(o, id);
      Queue(o.Text());
     }

   void              Fail(const long id, const string err)
     {
      CAiJsonOut o;
      o.Str("t", "reply");
      o.Int("id", id);
      o.Bool("ok", false);
      o.Str("err", err);
      Queue(o.Text());
     }

   double            RiskBase() const
     {
      return (m_cfg.riskBase == AI_BASE_BALANCE) ? AccountInfoDouble(ACCOUNT_BALANCE) : AccountInfoDouble(ACCOUNT_EQUITY);
     }

   //--- previews -----------------------------------------------------------
   int               FindPreview(const string pid) const
     {
      int n = ArraySize(m_pv);
      for(int i = 0; i < n; i++)
         if(m_pv[i].id == pid)
            return i;
      return -1;
     }

   int               AddPreview(const int kind, const string symbol)
     {
      int n = ArraySize(m_pv);
      if(n >= AI_PREVIEW_MAX)
        {
         for(int i = 1; i < n; i++)
            m_pv[i - 1] = m_pv[i];
         n--;
        }
      ArrayResize(m_pv, n + 1);
      ZeroMemory(m_pv[n]);
      m_pvSeq++;
      m_pv[n].id = "p" + IntegerToString(m_pvSeq);
      m_pv[n].kind = kind;
      m_pv[n].madeMs = AiNowMs();
      m_pv[n].login = AccountInfoInteger(ACCOUNT_LOGIN);
      m_pv[n].server = AccountInfoString(ACCOUNT_SERVER);
      m_pv[n].symbol = symbol;
      return n;
     }

   // The preview a confirm names, marked used. -1 (and the refusal sent) when it may not be used.
   int               UsePreview(const long id, const CAiJsonIn &in, const int kind)
     {
      int k = FindPreview(in.Str("preview"));
      if(k < 0 || m_pv[k].kind != kind)
        {
         Fail(id, "Unknown preview. Preview again");
         return -1;
        }
      if(m_pv[k].used)
        {
         Fail(id, "This preview was already confirmed. Preview again");
         return -1;
        }
      m_pv[k].used = true;
      if(AiNowMs() - m_pv[k].madeMs > AI_PREVIEW_TTL_MS)
        {
         Fail(id, "The preview is more than a minute old. Preview again");
         return -1;
        }
      // Login numbers repeat across brokers: the server must match too.
      if(m_pv[k].login != AccountInfoInteger(ACCOUNT_LOGIN) || m_pv[k].server != AccountInfoString(ACCOUNT_SERVER))
        {
         Fail(id, "MT5 is logged in to another account since the preview");
         return -1;
        }
      return k;
     }

   //--- what MT5 tells by itself --------------------------------------------
   string            TerminalJson()
     {
      CAiJsonOut o;
      o.Str("t", "terminal");
      o.Int("ver", AI_BRIDGE_VER);
      o.Int("login", AccountInfoInteger(ACCOUNT_LOGIN));
      o.Str("server", AccountInfoString(ACCOUNT_SERVER));
      o.Str("company", AccountInfoString(ACCOUNT_COMPANY));
      o.Str("currency", AccountInfoString(ACCOUNT_CURRENCY));
      o.Int("currencyDigits", AiMoneyDigits());
      o.Str("tradeMode", AiWordAccountMode());
      o.Str("marginMode", AiWordMarginMode());
      o.Bool("hedgeAllowed", AccountInfoInteger(ACCOUNT_HEDGE_ALLOWED) != 0);
      o.Bool("fifo", AccountInfoInteger(ACCOUNT_FIFO_CLOSE) != 0);
      o.Bool("connected", TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
      o.Str("problem", m_exec.PermissionProblem());
      o.Open("settings", false);
      o.Open("presets", true);
      for(int i = 0; i < 3; i++)
         o.Num("", m_cfg.preset[i]);
      o.Close(true);
      o.Str("riskBase", (m_cfg.riskBase == AI_BASE_BALANCE) ? "balance" : "equity");
      o.Num("maxRiskPct", m_cfg.maxRiskPct);
      o.Num("commissionRT", m_cfg.commissionRT);
      o.Bool("requireSL", m_cfg.requireSL);
      o.Bool("requireTP", m_cfg.requireTP);
      o.Str("pipMode", AiWordPipMode((int)m_cfg.pipMode));
      o.Num("defaultSLPips", m_cfg.defaultSLPips);
      o.Str("defaultTPMode", AiWordLevelMode((int)m_cfg.defaultTPMode));
      o.Num("defaultTPValue", m_cfg.defaultTPValue);
      o.Num("pendingOffsetPips", m_cfg.pendingOffsetPips);
      o.Str("slipPolicy", AiWordSlip(m_cfg.slipPolicy));
      o.Close(false);
      return o.Text();
     }

   string            QuoteJson(const MqlTick &tick) const
     {
      CAiJsonOut o;
      o.Str("t", "quote");
      o.Str("symbol", m_watch);
      o.Num("bid", tick.bid, m_watchSpec.digits);
      o.Num("ask", tick.ask, m_watchSpec.digits);
      o.Num("spreadPips", AiSafeDiv(tick.ask - tick.bid, m_watchSpec.pipSize), 1);
      o.Int("timeMsc", (long)tick.time_msc);
      return o.Text();
     }

   string            TradesJson(const AiLive &l[], const int n) const
     {
      CAiJsonOut o;
      o.Str("t", "trades");
      o.Num("balance", AccountInfoDouble(ACCOUNT_BALANCE));
      o.Num("equity", AccountInfoDouble(ACCOUNT_EQUITY));
      o.Num("margin", AccountInfoDouble(ACCOUNT_MARGIN));
      o.Num("freeMargin", AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      o.Open("list", true);
      for(int i = 0; i < n; i++)
        {
         int d = AiPriceDigits(l[i].symbol);
         o.Open("", false);
         o.Int("ticket", (long)l[i].ticket);
         o.Str("symbol", l[i].symbol);
         o.Str("kind", l[i].isOrder ? "order" : "position");
         o.Str("type", AiOrderTypeName(l[i].type));
         o.Int("side", l[i].side);
         o.Num("lots", l[i].lots);
         o.Num("open", l[i].open, d);
         o.Num("sl", l[i].sl, d);
         o.Num("tp", l[i].tp, d);
         o.Num("profit", l[i].profit);
         o.Int("digits", MathMax(d, 0));
         if(l[i].isOrder)
           {
            o.Int("expiration", (long)l[i].expiration);
            o.Bool("locked", AiIsStopLimit(l[i].type));
           }
         else
            o.Int("openMsc", l[i].openMsc);
         o.Close(false);
        }
      o.Close(true);
      return o.Text();
     }

   // Sends the trades when they changed, after a trade event, every second while positions are open
   // (their profit moves), or when forced.
   void              SendTrades(const bool force)
     {
      AiLive l[];
      int n = AiReadLive("", l);
      string sig = IntegerToString(n);
      bool positions = false;
      for(int i = 0; i < n; i++)
        {
         sig += "|" + IntegerToString((long)l[i].ticket) + ":" + DoubleToString(l[i].lots, 8) + ":" + DoubleToString(l[i].open, 8) + ":" +
                DoubleToString(l[i].sl, 8) + ":" + DoubleToString(l[i].tp, 8);
         if(!l[i].isOrder)
            positions = true;
        }
      ulong now = AiNowMs();
      bool due = force || m_tradeEvent || sig != m_lastTradesSig || (positions && now - m_lastTradesSentMs >= 1000);
      if(!due)
         return;
      m_tradeEvent = false;
      m_lastTradesSig = sig;
      m_lastTradesSentMs = now;
      Queue(TradesJson(l, n));
     }

   //--- requests -------------------------------------------------------------
   void              DoSymbols(const long id, const CAiJsonIn &in)
     {
      string ticker = AiTvTicker(in.Str("ticker"));
      if(AiSymNorm(ticker) == "")
        {
         Fail(id, "Missing ticker");
         return;
        }
      AiSymCand cands[];
      int n = AiSymbolCandidates(ticker, cands, 10);
      string pick = m_map.Pick(AccountInfoString(ACCOUNT_SERVER), ticker, cands);
      CAiJsonOut o;
      Begin(o, id);
      o.Str("ticker", ticker);
      o.Str("pick", pick);
      o.Open("candidates", true);
      for(int i = 0; i < n; i++)
        {
         o.Open("", false);
         o.Str("name", cands[i].name);
         o.Str("description", cands[i].description);
         o.Bool("visible", cands[i].visible);
         o.Int("rank", cands[i].rank);
         o.Close(false);
        }
      o.Close(true);
      Queue(o.Text());
     }

   void              DoPick(const long id, const CAiJsonIn &in)
     {
      string ticker = AiTvTicker(in.Str("ticker"));
      string symbol = in.Str("symbol");
      if(AiSymNorm(ticker) == "" || SymbolInfoDouble(symbol, SYMBOL_POINT) <= 0.0)
        {
         Fail(id, "Unknown ticker or symbol");
         return;
        }
      if(!m_map.Remember(AccountInfoString(ACCOUNT_SERVER), ticker, symbol))
        {
         Fail(id, "Could not save the choice");
         return;
        }
      Ok(id);
     }

   void              DoWatch(const long id, const CAiJsonIn &in)
     {
      string symbol = in.Str("symbol");
      if(SymbolInfoDouble(symbol, SYMBOL_POINT) <= 0.0)
        {
         Fail(id, "Unknown symbol " + symbol);
         return;
        }
      SymbolSelect(symbol, true);   // MT5 sends prices only for Market Watch symbols
      AiSpec s;
      AiLoadSpec(symbol, (int)m_cfg.pipMode, s);
      m_watch = symbol;
      m_watchSpec = s;
      m_lastBid = 0.0;
      m_lastAsk = 0.0;
      m_lastQuoteMs = 0;
      CAiJsonOut o;
      Begin(o, id);
      o.Open("spec", false);
      o.Str("symbol", symbol);
      o.Int("digits", s.digits);
      o.Num("point", s.point);
      o.Num("tickSize", s.tickSize);
      o.Num("pipSize", s.pipSize);
      o.Num("volMin", s.volMin);
      o.Num("volMax", s.volMax);
      o.Num("volStep", s.volStep);
      o.Int("stopsLevel", s.stopsLevel);
      o.Int("freezeLevel", s.freezeLevel);
      o.Str("execution", AiWordExecution(s.exeMode));
      o.Str("tradeMode", AiWordSymbolMode(s.tradeMode));
      o.Open("orders", false);
      bool any = (s.orderFlags == 0);
      o.Bool("market", any || (s.orderFlags & SYMBOL_ORDER_MARKET) != 0);
      o.Bool("limit", any || (s.orderFlags & SYMBOL_ORDER_LIMIT) != 0);
      o.Bool("stop", any || (s.orderFlags & SYMBOL_ORDER_STOP) != 0);
      o.Bool("sl", any || (s.orderFlags & SYMBOL_ORDER_SL) != 0);
      o.Bool("tp", any || (s.orderFlags & SYMBOL_ORDER_TP) != 0);
      o.Close(false);
      o.Num("contractSize", s.contractSize);
      o.Str("base", SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE));
      o.Str("profit", SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT));
      o.Close(false);
      Queue(o.Text());
     }

   // What the trader entered, read from a preview request; "" or why it can't be read.
   string            ReadInput(const CAiJsonIn &in, AiInput &x) const
     {
      ZeroMemory(x);
      x.side = AiParseSide(in.Str("side"));
      if(x.side == 0)
         return "side must be \"buy\" or \"sell\"";
      x.pending = in.Bool("pending", false);
      x.entry = in.Num("entry", 0.0);
      x.slMode = AiParseLevelMode(in.Str("slMode", "pips"), false);
      x.tpMode = AiParseLevelMode(in.Str("tpMode", "r"), true);
      if(x.slMode < 0 || x.tpMode < 0)
         return "Unknown SL or TP mode";
      x.slValue = in.Num("slValue", 0.0);
      x.tpValue = in.Num("tpValue", 0.0);
      x.riskMode = AiParseRiskMode(in.Str("riskMode", "percent"));
      if(x.riskMode < 0)
         return "Unknown risk mode";
      x.riskValue = in.Num("riskValue", 0.0);
      x.riskBase = (in.Str("riskBase", "equity") == "balance") ? AI_BASE_BALANCE : AI_BASE_EQUITY;
      if(x.entry < 0.0 || x.slValue < 0.0 || x.tpValue < 0.0 || x.riskValue < 0.0)
         return "Values can't be negative";
      return "";
     }

   void              PlanFields(CAiJsonOut &o, const AiSpec &s, const AiPlan &p) const
     {
      o.Bool("valid", p.valid);
      o.Str("err", p.err);
      o.Str("warn", p.warn);
      o.Str("type", AiOrderTypeName(p.type));
      o.Num("entry", p.entry, s.digits);
      o.Num("sl", p.sl, s.digits);
      o.Num("tp", p.tp, s.digits);
      o.Num("lots", p.lots, s.volDigits);
      o.Num("riskMoney", p.riskMoney);
      o.Num("riskPct", p.riskPct);
      o.Num("rewardMoney", p.rewardMoney);
      o.Num("rewardPct", p.rewardPct);
      o.Num("rr", p.rr);
      o.Num("slPips", p.slPips, 1);
      o.Num("tpPips", p.tpPips, 1);
      o.Num("pipValue", p.pipValue);
      o.Num("margin", p.margin);
      o.Num("freeAfter", p.freeAfter);
      o.Num("commission", p.commission);
      o.Num("spreadPips", p.spreadPips, 1);
      o.Num("bid", p.bid, s.digits);
      o.Num("ask", p.ask, s.digits);
     }

   void              DoPreview(const long id, const CAiJsonIn &in)
     {
      string symbol = in.Str("symbol");
      if(SymbolInfoDouble(symbol, SYMBOL_POINT) <= 0.0)
        {
         Fail(id, "Unknown symbol " + symbol);
         return;
        }
      AiInput x;
      string why = ReadInput(in, x);
      if(why != "")
        {
         Fail(id, why);
         return;
        }
      AiSpec s;
      AiLoadSpec(symbol, (int)m_cfg.pipMode, s);
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(symbol, tick);
      AiPlan p;
      AiBuildPlan(s, x, m_cfg, tick, p);
      int k = AddPreview(AI_PV_NEW, symbol);
      m_pv[k].in = x;
      m_pv[k].seenRisk = p.riskMoney;
      m_pv[k].seenLots = p.lots;
      m_pv[k].type = p.type;
      CAiJsonOut o;
      Begin(o, id);
      o.Str("preview", m_pv[k].id);
      o.Open("plan", false);
      PlanFields(o, s, p);
      o.Close(false);
      Queue(o.Text());
     }

   void              DoSend(const long id, const CAiJsonIn &in)
     {
      int k = UsePreview(id, in, AI_PV_NEW);
      if(k < 0)
         return;
      string perm = m_exec.PermissionProblem();
      if(perm != "")
        {
         Fail(id, perm);
         return;
        }
      AiPreview pv = m_pv[k];
      AiSpec s;
      AiPlan p;
      AiSendResult r;
      ZeroMemory(r);
      for(int attempt = 0; attempt < 3; attempt++)
        {
         AiLoadSpec(pv.symbol, (int)m_cfg.pipMode, s);
         MqlTick tick;
         ZeroMemory(tick);
         SymbolInfoTick(pv.symbol, tick);
         AiBuildPlan(s, pv.in, m_cfg, tick, p);
         if(!p.valid)
           {
            Fail(id, p.err);
            return;
           }
         // A pending entry the price crossed would now be the other type (a limit becomes a stop).
         if(p.type != pv.type)
           {
            Fail(id, "The price crossed the entry since the preview: it would be a " + AiOrderTypeName(p.type) + " now. Check it and confirm again");
            return;
           }
         if(MathAbs(p.lots - pv.seenLots) > s.volStep * 0.5)
           {
            Fail(id, "The lots changed since the preview (" + AiLotsStr(s, pv.seenLots) + " to " + AiLotsStr(s, p.lots) + "). Check them and confirm again");
            return;
           }
         if(pv.seenRisk > 0.0 && p.riskMoney > pv.seenRisk * 1.05 + 0.01)
           {
            Fail(id, "The risk grew since the preview. Check it and confirm again");
            return;
           }
         if(m_exec.Send(s, p, m_cfg, r))
           {
            Sent(id, pv, s, p, r);
            return;
           }
         if(r.retcode != TRADE_RETCODE_REQUOTE && r.retcode != TRADE_RETCODE_PRICE_CHANGED && r.retcode != TRADE_RETCODE_PRICE_OFF)
            break;
        }
      AiLog("Browser panel: not sent: " + r.msg + " | " + AiOrderTypeName(p.type) + " " + AiLotsStr(s, p.lots) + " " + pv.symbol);
      Fail(id, "Not sent: " + ((r.msg != "") ? r.msg : "unknown error"));
     }

   void              Sent(const long id, const AiPreview &pv, const AiSpec &s, const AiPlan &p, const AiSendResult &r)
     {
      AiMem m;
      if(AiMemFromPlan(p, pv.in.side, pv.in.slMode, pv.in.tpMode, pv.in.tpValue, (long)TimeCurrent(), m))
        {
         AiMem mem[];
         AiMemLoad(pv.symbol, mem);
         AiMemPush(mem, m);
         if(!AiMemSave(pv.symbol, mem))
            AiLog("Could not save the SL/TP memory file");
        }
      AiFillReport f;
      AiAfterFill(m_exec, s, p, m_cfg, pv.in.slMode, pv.in.tpMode, pv.in.tpValue, r, f);
      AiLog("Browser panel: " + AiOrderTypeName(p.type) + " " + AiLotsStr(s, r.volume) + " " + pv.symbol + (p.pending ? " placed at " : " filled at ") +
            AiPriceStr(s, r.price) + " | SL " + AiPriceStr(s, f.sl) + " TP " + AiPriceStr(s, f.tp) + " | risk " + DoubleToString(f.risk, 2) +
            ((f.notMoved != "") ? " | not moved: " + f.notMoved : "") + " | ticket " + IntegerToString((long)r.ticket));
      CAiJsonOut o;
      Begin(o, id);
      o.Int("ticket", (long)r.ticket);
      o.Str("type", AiOrderTypeName(p.type));
      o.Bool("pending", p.pending);
      o.Num("price", r.price, s.digits);
      o.Num("lots", r.volume, s.volDigits);
      o.Open("fill", false);
      o.Bool("slipped", f.slipped);
      o.Num("slipPips", f.slipPips, 1);
      o.Bool("slMoved", f.slMoved);
      o.Bool("tpMoved", f.tpMoved);
      o.Str("notMoved", f.notMoved);
      o.Num("sl", f.sl, s.digits);
      o.Num("tp", f.tp, s.digits);
      o.Num("risk", f.risk);
      o.Num("plannedRisk", p.riskMoney);
      o.Close(false);
      Queue(o.Text());
      m_tradeEvent = true;
     }

   void              DoRecall(const long id, const CAiJsonIn &in)
     {
      string symbol = in.Str("symbol");
      int side = AiParseSide(in.Str("side"));
      if(side == 0 || SymbolInfoDouble(symbol, SYMBOL_POINT) <= 0.0)
        {
         Fail(id, "Unknown symbol or side");
         return;
        }
      string which = in.Str("which", "both");
      bool doSL = (which != "tp");
      bool doTP = (which != "sl");
      string what = (doSL && doTP) ? "SL/TP" : (doSL ? "stop loss" : "take profit");
      AiSpec s;
      AiLoadSpec(symbol, (int)m_cfg.pipMode, s);
      AiMem mem[];
      int n = AiMemLoad(symbol, mem);
      AiMem m;
      ZeroMemory(m);
      if(n == 0 && !AiMemFromHistory(symbol, m))
        {
         Fail(id, "No earlier " + what + " saved for " + symbol);
         return;
        }
      double entry = in.Num("entry", 0.0);
      if(entry <= 0.0)
        {
         MqlTick tick;
         ZeroMemory(tick);
         SymbolInfoTick(symbol, tick);
         entry = (side == AI_BUY) ? tick.ask : tick.bid;
        }
      // From record 'back' on, the first that holds the asked levels, as the chart's Last buttons
      // (App.mqh RecallLevel).
      long back = MathMax(in.Int("back", 0), (long)0);
      int tries = (n > 0) ? n : 1;
      for(int k = 0; k < tries; k++)
        {
         int idx = (n > 0) ? (int)((back + k) % n) : 0;
         if(n > 0)
            m = mem[idx];
         int slMode = AI_LEVEL_PIPS;
         double slValue = m_cfg.defaultSLPips;
         int tpMode = (int)m_cfg.defaultTPMode;
         double tpValue = m_cfg.defaultTPValue;
         string desc = "";
         if(!AiRecallLevels(s, m, side, entry, doSL, doTP, slMode, slValue, tpMode, tpValue, desc))
            continue;
         CAiJsonOut o;
         Begin(o, id);
         o.Str("slMode", AiWordLevelMode(slMode));
         o.Num("slValue", slValue);
         o.Str("tpMode", AiWordLevelMode(tpMode));
         o.Num("tpValue", tpValue);
         o.Str("desc", desc);
         o.Int("index", idx);
         o.Int("count", n);
         Queue(o.Text());
         return;
        }
      Fail(id, "No earlier " + what + " saved for " + symbol);
     }

   void              ModFields(CAiJsonOut &o, const AiSpec &s, const AiModPlan &m) const
     {
      o.Bool("valid", m.valid);
      o.Bool("changed", m.changed);
      o.Str("err", m.err);
      o.Str("warn", m.warn);
      o.Num("open", m.open, s.digits);
      o.Num("sl", m.sl, s.digits);
      o.Num("tp", m.tp, s.digits);
      o.Num("slMoney", m.slMoney);
      o.Num("slPct", m.slPct);
      o.Num("oldSlMoney", m.oldSlMoney);
      o.Num("tpMoney", m.tpMoney);
      o.Num("tpPct", m.tpPct);
      o.Num("rr", m.rr);
      o.Num("slPips", m.slPips, 1);
      o.Num("tpPips", m.tpPips, 1);
      o.Str("type", AiOrderTypeName(m.type));
      o.Bool("retype", m.retype);
     }

   void              DoModPreview(const long id, const CAiJsonIn &in)
     {
      ulong ticket = (ulong)in.Int("ticket", 0);
      AiLive l;
      if(!AiFindLive(ticket, l))
        {
         Fail(id, "#" + IntegerToString((long)ticket) + " is not open");
         return;
        }
      double open = (l.isOrder && in.Has("open")) ? in.Num("open", l.open) : l.open;
      double sl = in.Has("sl") ? in.Num("sl", l.sl) : l.sl;
      double tp = in.Has("tp") ? in.Num("tp", l.tp) : l.tp;
      AiSpec s;
      AiLoadSpec(l.symbol, (int)m_cfg.pipMode, s);
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(l.symbol, tick);
      AiModPlan m;
      AiBuildModPlan(s, l, open, sl, tp, m_cfg, tick, RiskBase(), m);
      int k = AddPreview(AI_PV_MOD, l.symbol);
      m_pv[k].ticket = ticket;
      m_pv[k].open = m.open;
      m_pv[k].sl = m.sl;
      m_pv[k].tp = m.tp;
      m_pv[k].type = m.type;
      m_pv[k].wasOpen = l.open;
      m_pv[k].wasSl = l.sl;
      m_pv[k].wasTp = l.tp;
      m_pv[k].wasLots = l.lots;
      CAiJsonOut o;
      Begin(o, id);
      o.Str("preview", m_pv[k].id);
      o.Open("mod", false);
      ModFields(o, s, m);
      o.Close(false);
      Queue(o.Text());
     }

   // The trade changed on the server since the preview: its levels, entry or size.
   bool              ChangedSince(const AiPreview &pv, const AiLive &l, const AiSpec &s) const
     {
      double eps = MathMax(s.point, 1e-10) * 0.5;
      return MathAbs(l.open - pv.wasOpen) > eps || MathAbs(l.sl - pv.wasSl) > eps || MathAbs(l.tp - pv.wasTp) > eps ||
             MathAbs(l.lots - pv.wasLots) > 1e-9;
     }

   void              DoModSend(const long id, const CAiJsonIn &in)
     {
      int k = UsePreview(id, in, AI_PV_MOD);
      if(k < 0)
         return;
      AiPreview pv = m_pv[k];
      string perm = m_exec.PermissionProblem();
      if(perm != "")
        {
         Fail(id, perm);
         return;
        }
      AiLive l;
      if(!AiFindLive(pv.ticket, l))
        {
         Fail(id, "#" + IntegerToString((long)pv.ticket) + " is no longer open. Nothing was changed");
         return;
        }
      AiSpec s;
      AiLoadSpec(l.symbol, (int)m_cfg.pipMode, s);
      if(ChangedSince(pv, l, s))
        {
         Fail(id, "#" + IntegerToString((long)pv.ticket) + " changed since the preview. Check it and confirm again");
         return;
        }
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(l.symbol, tick);
      AiModPlan m;
      AiBuildModPlan(s, l, pv.open, pv.sl, pv.tp, m_cfg, tick, RiskBase(), m);
      if(!m.valid)
        {
         Fail(id, (m.err != "") ? m.err : "Nothing to change");
         return;
        }
      if(m.type != pv.type)
        {
         Fail(id, "The price moved across the entry since the preview: the order would be a " + AiOrderTypeName(m.type) + " now. Check it and confirm again");
         return;
        }
      AiSendResult r;
      string was = "#" + IntegerToString((long)l.ticket) + " " + AiOrderTypeName(l.type);
      if(m.retype)
        {
         if(!m_exec.Replace(s, l, m.type, m.open, m.sl, m.tp, r))
           {
            m_tradeEvent = r.removed;
            string why = (r.removed) ? "The " + was + " was removed, but the " + AiOrderTypeName(m.type) + " was refused: " + r.msg +
                                       ". No order is pending now" : "Not changed: " + r.msg;
            AiLog("Browser panel: " + why);
            CAiJsonOut f;
            f.Str("t", "reply");
            f.Int("id", id);
            f.Bool("ok", false);
            f.Str("err", why);
            f.Bool("removed", r.removed);
            Queue(f.Text());
            return;
           }
         AiLog("Browser panel: " + was + " " + l.symbol + " replaced by #" + IntegerToString((long)r.ticket) + " " + AiOrderTypeName(m.type) +
               " at " + AiPriceStr(s, m.open) + " | SL " + AiPriceStr(s, m.sl) + " TP " + AiPriceStr(s, m.tp));
        }
      else if(!m_exec.Modify(s, l, m.open, m.sl, m.tp, r))
        {
         Fail(id, "Not changed: " + r.msg);
         return;
        }
      else
         AiLog("Browser panel: changed #" + IntegerToString((long)l.ticket) + " " + l.symbol + ": SL " + AiPriceStr(s, m.sl) + " TP " +
               AiPriceStr(s, m.tp) + (l.isOrder ? " entry " + AiPriceStr(s, m.open) : ""));
      CAiJsonOut o;
      Begin(o, id);
      o.Int("ticket", (long)(m.retype ? r.ticket : l.ticket));
      o.Str("type", AiOrderTypeName(m.type));
      o.Bool("replaced", m.retype);
      Queue(o.Text());
      m_tradeEvent = true;
     }

   void              DoClosePreview(const long id, const CAiJsonIn &in)
     {
      ulong ticket = (ulong)in.Int("ticket", 0);
      AiLive l;
      if(!AiFindLive(ticket, l) || l.isOrder)
        {
         Fail(id, "#" + IntegerToString((long)ticket) + " is not an open position");
         return;
        }
      AiSpec s;
      AiLoadSpec(l.symbol, (int)m_cfg.pipMode, s);
      double lots = in.Num("lots", 0.0);
      if(lots <= 0.0)
         lots = l.lots;
      double left = 0.0;
      string err = AiCheckClose(s, l, lots, left);
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(l.symbol, tick);
      double price = (l.side == AI_BUY) ? tick.bid : tick.ask;
      int k = AddPreview(AI_PV_CLOSE, l.symbol);
      m_pv[k].ticket = ticket;
      m_pv[k].lots = lots;
      m_pv[k].wasOpen = l.open;
      m_pv[k].wasSl = l.sl;
      m_pv[k].wasTp = l.tp;
      m_pv[k].wasLots = l.lots;
      CAiJsonOut o;
      Begin(o, id);
      o.Str("preview", m_pv[k].id);
      o.Open("close", false);
      o.Bool("valid", err == "");
      o.Str("err", err);
      o.Num("lots", lots, s.volDigits);
      o.Num("left", left, s.volDigits);
      o.Num("price", price, s.digits);
      o.Num("profit", (l.lots > 0.0) ? l.profit * lots / l.lots : 0.0);
      o.Close(false);
      Queue(o.Text());
     }

   void              DoClose(const long id, const CAiJsonIn &in)
     {
      int k = UsePreview(id, in, AI_PV_CLOSE);
      if(k < 0)
         return;
      AiPreview pv = m_pv[k];
      string perm = m_exec.PermissionProblem();
      if(perm != "")
        {
         Fail(id, perm);
         return;
        }
      AiLive l;
      if(!AiFindLive(pv.ticket, l) || l.isOrder)
        {
         Fail(id, "#" + IntegerToString((long)pv.ticket) + " is already closed");
         return;
        }
      if(MathAbs(l.lots - pv.wasLots) > 1e-9)
        {
         Fail(id, "#" + IntegerToString((long)pv.ticket) + " changed size since the preview. Check it and confirm again");
         return;
        }
      AiSpec s;
      AiLoadSpec(l.symbol, (int)m_cfg.pipMode, s);
      double left = 0.0;
      string err = AiCheckClose(s, l, pv.lots, left);
      if(err != "")
        {
         Fail(id, err);
         return;
        }
      AiSendResult r;
      if(!m_exec.Close(s, l, pv.lots, m_cfg, r))
        {
         Fail(id, "Not closed: " + r.msg);
         return;
        }
      AiLog("Browser panel: closed " + AiLotsStr(s, r.volume) + " of #" + IntegerToString((long)l.ticket) + " " + l.symbol + " at " +
            AiPriceStr(s, r.price));
      CAiJsonOut o;
      Begin(o, id);
      o.Int("ticket", (long)l.ticket);
      o.Num("price", r.price, s.digits);
      o.Num("lots", r.volume, s.volDigits);
      Queue(o.Text());
      m_tradeEvent = true;
     }

   void              DoCancel(const long id, const CAiJsonIn &in)
     {
      ulong ticket = (ulong)in.Int("ticket", 0);
      AiLive l;
      if(!AiFindLive(ticket, l) || !l.isOrder)
        {
         Fail(id, "#" + IntegerToString((long)ticket) + " is not a pending order");
         return;
        }
      string perm = m_exec.PermissionProblem();
      if(perm != "")
        {
         Fail(id, perm);
         return;
        }
      AiSpec s;
      AiLoadSpec(l.symbol, (int)m_cfg.pipMode, s);
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(l.symbol, tick);
      string err = AiCheckCancel(s, l, tick.bid, tick.ask);
      if(err != "")
        {
         Fail(id, err);
         return;
        }
      AiSendResult r;
      if(!m_exec.Remove(ticket, r))
        {
         Fail(id, "Not removed: " + r.msg);
         return;
        }
      AiLog("Browser panel: removed #" + IntegerToString((long)ticket) + " " + l.symbol);
      Ok(id);
      m_tradeEvent = true;
     }

public:
                     CAiBridge() : m_pvSeq(0), m_lastBid(0.0), m_lastAsk(0.0), m_lastQuoteMs(0), m_lastTerminalMs(0),
                     m_lastTradesCheckMs(0), m_lastTradesSentMs(0), m_tradeEvent(false) {}

   void              Init(const AiSettings &cfg)
     {
      m_cfg = cfg;
      ArrayResize(m_out, 0);
      ArrayResize(m_pv, 0);
      m_pvSeq = 0;
      m_watch = "";
      m_lastTerminal = "";
      m_lastTradesSig = "";
     }

   // The pipe (re)connected: the panel learns the terminal and the trades at once.
   void              Start()
     {
      ArrayResize(m_pv, 0);
      m_watch = "";
      m_lastTerminal = TerminalJson();
      m_lastTerminalMs = AiNowMs();
      Queue(m_lastTerminal);
      SendTrades(true);
     }

   void              OnTrade()
     {
      m_tradeEvent = true;
     }

   // What MT5 tells the panel by itself. Called on every timer tick of the link.
   void              Poll()
     {
      ulong now = AiNowMs();
      if(now - m_lastTerminalMs >= 1000)
        {
         m_lastTerminalMs = now;
         string tj = TerminalJson();
         if(tj != m_lastTerminal)
           {
            m_lastTerminal = tj;
            Queue(tj);
           }
        }
      if(m_watch != "" && now - m_lastQuoteMs >= 100)
        {
         MqlTick tick;
         ZeroMemory(tick);
         if(SymbolInfoTick(m_watch, tick) && tick.bid > 0.0 && (tick.bid != m_lastBid || tick.ask != m_lastAsk))
           {
            m_lastBid = tick.bid;
            m_lastAsk = tick.ask;
            m_lastQuoteMs = now;
            Queue(QuoteJson(tick));
           }
        }
      if(m_tradeEvent || now - m_lastTradesCheckMs >= 250)
        {
         m_lastTradesCheckMs = now;
         SendTrades(false);
        }
     }

   void              Handle(const string line)
     {
      CAiJsonIn in;
      if(!in.Parse(line))
        {
         CAiJsonOut o;
         o.Str("t", "error");
         o.Str("err", in.Error());
         Queue(o.Text());
         return;
        }
      string t = in.Str("t");
      long id = in.Int("id", 0);
      if(id <= 0)
        {
         CAiJsonOut o;
         o.Str("t", "error");
         o.Str("err", "A request needs a positive id");
         Queue(o.Text());
         return;
        }
      if(t == "symbols")
         DoSymbols(id, in);
      else if(t == "pick")
         DoPick(id, in);
      else if(t == "watch")
         DoWatch(id, in);
      else if(t == "preview")
         DoPreview(id, in);
      else if(t == "send")
         DoSend(id, in);
      else if(t == "recall")
         DoRecall(id, in);
      else if(t == "modPreview")
         DoModPreview(id, in);
      else if(t == "modSend")
         DoModSend(id, in);
      else if(t == "closePreview")
         DoClosePreview(id, in);
      else if(t == "close")
         DoClose(id, in);
      else if(t == "cancel")
         DoCancel(id, in);
      else
         Fail(id, "Unknown request: " + t);
     }

   // Moves the queued messages out, oldest first.
   int               TakeOut(string &out[])
     {
      int n = ArraySize(m_out);
      ArrayResize(out, n);
      for(int i = 0; i < n; i++)
         out[i] = m_out[i];
      ArrayResize(m_out, 0);
      return n;
     }
  };

#endif
