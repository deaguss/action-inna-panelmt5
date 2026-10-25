//+------------------------------------------------------------------+
//| ActionInna - trade permissions and sending orders                |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_EXECUTOR_MQH
#define ACTIONINNA_EXECUTOR_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "SymbolSpec.mqh"
#include "RiskCalc.mqh"
#include "Trades.mqh"

struct AiSendResult
  {
   bool              ok;
   uint              retcode;
   ulong             ticket;
   double            price;
   double            volume;
   string            msg;
  };

void AiAddFill(ENUM_ORDER_TYPE_FILLING &arr[], const ENUM_ORDER_TYPE_FILLING f)
  {
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
      if(arr[i] == f)
         return;
   ArrayResize(arr, n + 1);
   arr[n] = f;
  }

// Filling modes to try, best first. RETURN is never allowed for market orders in Market
// execution, but it is the normal mode of a pending order.
int AiFillingOrder(const AiSpec &s, const bool pending, ENUM_ORDER_TYPE_FILLING &out[])
  {
   ArrayResize(out, 0);
   bool fok = (s.fillingFlags & SYMBOL_FILLING_FOK) != 0;
   bool ioc = (s.fillingFlags & SYMBOL_FILLING_IOC) != 0;
   bool marketExec = (s.exeMode == SYMBOL_TRADE_EXECUTION_MARKET);
   if(pending)
      AiAddFill(out, ORDER_FILLING_RETURN);
   if(fok)
      AiAddFill(out, ORDER_FILLING_FOK);
   if(ioc)
      AiAddFill(out, ORDER_FILLING_IOC);
   if(!pending && !marketExec)
      AiAddFill(out, ORDER_FILLING_RETURN);
   if(ArraySize(out) == 0)
     {
      AiAddFill(out, ORDER_FILLING_FOK);
      AiAddFill(out, ORDER_FILLING_IOC);
      AiAddFill(out, ORDER_FILLING_RETURN);
     }
   return ArraySize(out);
  }

void AiMoveFillToFront(ENUM_ORDER_TYPE_FILLING &arr[], const int fill)
  {
   int n = ArraySize(arr);
   for(int i = 1; i < n; i++)
      if((int)arr[i] == fill)
        {
         ENUM_ORDER_TYPE_FILLING f = arr[i];
         for(int j = i; j > 0; j--)
            arr[j] = arr[j - 1];
         arr[0] = f;
         return;
        }
  }

// Good till cancelled when the symbol allows it, else the end of the day, else a date 30 days out.
ENUM_ORDER_TYPE_TIME AiPendingTime(const AiSpec &s, datetime &expiration)
  {
   expiration = 0;
   if(s.expirationFlags == 0 || (s.expirationFlags & SYMBOL_EXPIRATION_GTC) != 0)
      return ORDER_TIME_GTC;
   if((s.expirationFlags & SYMBOL_EXPIRATION_DAY) != 0)
      return ORDER_TIME_DAY;
   expiration = TimeCurrent() + 30 * 86400;
   if((s.expirationFlags & SYMBOL_EXPIRATION_SPECIFIED) != 0)
      return ORDER_TIME_SPECIFIED;
   if((s.expirationFlags & SYMBOL_EXPIRATION_SPECIFIED_DAY) != 0)
      return ORDER_TIME_SPECIFIED_DAY;
   expiration = 0;
   return ORDER_TIME_GTC;
  }

// Plain words for the trade server's return codes.
string AiRetcodeText(const uint code)
  {
   switch(code)
     {
      case 10004:
         return "Requote";
      case 10006:
         return "Rejected by the server";
      case 10007:
         return "Cancelled";
      case 10011:
         return "Request error";
      case 10012:
         return "Timed out";
      case 10013:
         return "Invalid request";
      case 10014:
         return "Invalid volume";
      case 10015:
         return "Invalid price";
      case 10016:
         return "Invalid SL or TP";
      case 10017:
         return "Trading is disabled";
      case 10018:
         return "Market is closed";
      case 10019:
         return "Not enough money";
      case 10020:
         return "Prices changed";
      case 10021:
         return "No quotes";
      case 10022:
         return "Invalid expiration";
      case 10023:
         return "Order state changed";
      case 10024:
         return "Too many requests";
      case 10025:
         return "Nothing to change";
      case 10026:
         return "The server disabled algo trading";
      case 10027:
         return "Algo Trading is off in the terminal";
      case 10028:
         return "Request locked";
      case 10029:
         return "Order or position frozen";
      case 10030:
         return "Unsupported filling mode";
      case 10031:
         return "No connection to the server";
      case 10032:
         return "Allowed on live accounts only";
      case 10033:
         return "Pending order limit reached";
      case 10034:
         return "Volume limit reached";
      case 10035:
         return "Invalid order type";
      case 10040:
         return "Position limit reached";
      case 10042:
         return "Only buys are allowed";
      case 10043:
         return "Only sells are allowed";
      case 10044:
         return "Only closing is allowed";
      case 10046:
         return "Hedging is not allowed";
     }
   return "Error";
  }

// Why a request did not go through, in words.
string AiResultText(const MqlTradeResult &res)
  {
   if(res.retcode == 0)
      return "OrderSend failed, error " + IntegerToString(GetLastError());
   string msg = AiRetcodeText(res.retcode) + " (" + IntegerToString((int)res.retcode) + ")";
   if(res.comment != "")
      msg += ": " + res.comment;
   return msg;
  }

class CAiExecutor
  {
private:
   string            m_fillSymbol;
   int               m_fillMarket;    // filling mode that worked last, -1 = unknown
   int               m_fillPending;

public:
                     CAiExecutor() : m_fillSymbol(""), m_fillMarket(-1), m_fillPending(-1) {}

   // "" when this EA may trade now, otherwise what to fix.
   string            PermissionProblem() const
     {
      if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
         return "No connection to the trade server";
      if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
         return "Turn on Algo Trading (toolbar button) to send orders";
      if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
         return "Tick 'Allow Algo Trading' in the EA's Common tab";
      if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0)
         return "This account cannot trade (investor login?)";
      if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT) == 0)
         return "The broker does not allow EAs on this account";
      return "";
     }

   // Sends the plan as it is. On "unsupported filling mode" the next allowed mode is tried.
   bool              Send(const AiSpec &s, const AiPlan &p, const AiSettings &cfg, AiSendResult &r)
     {
      ZeroMemory(r);
      if(m_fillSymbol != s.symbol)
        {
         m_fillSymbol = s.symbol;
         m_fillMarket = -1;
         m_fillPending = -1;
        }
      ENUM_ORDER_TYPE_FILLING fills[];
      int nf = AiFillingOrder(s, p.pending, fills);
      int last = p.pending ? m_fillPending : m_fillMarket;
      if(last >= 0)
         AiMoveFillToFront(fills, last);
      for(int i = 0; i < nf; i++)
        {
         MqlTradeRequest req;
         MqlTradeResult res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action = p.pending ? TRADE_ACTION_PENDING : TRADE_ACTION_DEAL;
         req.symbol = s.symbol;
         req.volume = p.lots;
         req.type = p.type;
         req.price = p.entry;
         req.sl = p.sl;
         req.tp = p.tp;
         req.deviation = (ulong)MathMax(cfg.deviation, 0);
         req.magic = cfg.magic;
         req.comment = cfg.comment;
         req.type_filling = fills[i];
         if(p.pending)
           {
            datetime expiration = 0;
            req.type_time = AiPendingTime(s, expiration);
            req.expiration = expiration;
           }
         ResetLastError();
         bool sent = OrderSend(req, res);
         r.retcode = res.retcode;
         if(res.retcode == TRADE_RETCODE_INVALID_FILL && i < nf - 1)
            continue;
         if(sent && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE_PARTIAL))
           {
            if(p.pending)
               m_fillPending = (int)fills[i];
            else
               m_fillMarket = (int)fills[i];
            r.ok = true;
            r.ticket = (res.order > 0) ? res.order : res.deal;
            r.price = (res.price > 0.0) ? res.price : p.entry;
            r.volume = (res.volume > 0.0) ? res.volume : p.lots;
            return true;
           }
         r.msg = AiResultText(res);
         return false;
        }
      return false;
     }

   // Changes a position's SL/TP, or a pending order's price and SL/TP. A pending order keeps its
   // own expiry and stop-limit price.
   bool              Modify(const AiSpec &s, const AiLive &l, const double open, const double sl, const double tp, AiSendResult &r)
     {
      ZeroMemory(r);
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.symbol = s.symbol;
      req.sl = sl;
      req.tp = tp;
      if(l.isOrder)
        {
         req.action = TRADE_ACTION_MODIFY;
         req.order = l.ticket;
         req.price = open;
         req.stoplimit = l.stopLimit;
         req.type_time = (ENUM_ORDER_TYPE_TIME)l.timeType;
         req.expiration = l.expiration;
        }
      else
        {
         req.action = TRADE_ACTION_SLTP;
         req.position = l.ticket;
        }
      ResetLastError();
      bool sent = OrderSend(req, res);
      r.retcode = res.retcode;
      if(sent && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
        {
         r.ok = true;
         r.ticket = l.ticket;
         r.price = l.isOrder ? open : l.open;
         r.volume = l.lots;
         return true;
        }
      r.msg = AiResultText(res);
      return false;
     }
  };

// A market order that filled a tick or more away from its planned entry: moves its SL and TP as
// cfg.slipPolicy says (AiFollowFill), and reports where they are and what the stop now risks. The
// position already carries the planned SL and TP, so it is never without them meanwhile. A netting
// position the order only joined keeps its levels: they belong to more than this order.
void AiAfterFill(CAiExecutor &exec, const AiSpec &s, const AiPlan &p, const AiSettings &cfg, const int slMode, const int tpMode,
                 const double tpR, const AiSendResult &r, AiFillReport &f)
  {
   ZeroMemory(f);
   f.sl = p.sl;
   f.tp = p.tp;
   f.risk = p.riskMoney;
   if(p.pending || r.price <= 0.0)
      return;
   double half = MathMax(s.tickSize, s.point) * 0.5;
   if(MathAbs(r.price - p.entry) < half)
      return;
   f.slipped = true;
   f.slipPips = AiSafeDiv((r.price - p.entry) * p.side, s.pipSize);
   AiLive l;
   if(!AiFindPosition(s.symbol, r.ticket, l))
     {
      f.notMoved = "the position was not found";
      return;
     }
   bool joined = (MathAbs(l.lots - r.volume) > s.volStep * 0.5 || MathAbs(l.open - r.price) >= half);
   double newSl = l.sl;
   double newTp = l.tp;
   if(joined)
      f.notMoved = "the order joined the open position, whose SL/TP stay";
   else if(AiFollowFill(s, cfg.slipPolicy, p.side, p.entry, r.price, slMode, tpMode, tpR, l.sl, l.tp, newSl, newTp))
     {
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(s.symbol, tick);
      string why = AiCheckModify(s, l, l.open, newSl, newTp, tick.bid, tick.ask);
      AiSendResult mr;
      ZeroMemory(mr);
      if(why == "" && exec.Modify(s, l, l.open, newSl, newTp, mr))
        {
         f.slMoved = (MathAbs(newSl - l.sl) >= half);
         f.tpMoved = (MathAbs(newTp - l.tp) >= half);
         l.sl = newSl;
         l.tp = newTp;
        }
      else
         f.notMoved = (why != "") ? why : mr.msg;
     }
   f.sl = l.sl;
   f.tp = l.tp;
   double comm = MathMax(cfg.commissionRT, 0.0) * r.volume;
   double loss = 0.0;
   f.risk = (f.sl > 0.0 && AiLossPerLot(s, p.side, r.price, f.sl, loss)) ? loss * r.volume + comm : comm;
  }

#endif
