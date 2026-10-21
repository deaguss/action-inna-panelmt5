//+------------------------------------------------------------------+
//| ActionInna - turns what the trader entered into an order plan    |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_RISKCALC_MQH
#define ACTIONINNA_RISKCALC_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "SymbolSpec.mqh"

// Market orders keep their side. A pending buy below the ask is a limit and above it a stop;
// a pending sell above the bid is a limit and below it a stop. ok is false at the market price.
ENUM_ORDER_TYPE AiResolveType(const int side, const bool pending, const double entry, const double bid, const double ask, bool &ok)
  {
   ok = true;
   if(!pending)
      return (side == AI_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(side == AI_BUY)
     {
      if(entry < ask)
         return ORDER_TYPE_BUY_LIMIT;
      if(entry > ask)
         return ORDER_TYPE_BUY_STOP;
     }
   else
     {
      if(entry > bid)
         return ORDER_TYPE_SELL_LIMIT;
      if(entry < bid)
         return ORDER_TYPE_SELL_STOP;
     }
   ok = false;
   return (side == AI_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
  }

bool AiIsBuyType(const ENUM_ORDER_TYPE type)
  {
   return (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP);
  }

// "" when SL and TP sit on the right side and respect the broker's stops level, else why not.
// A buy's SL and TP trigger on the bid, a sell's on the ask; pending levels count from the entry.
string AiCheckStops(const AiSpec &s, const ENUM_ORDER_TYPE type, const double entry, const double sl, const double tp, const double bid, const double ask)
  {
   bool buy = AiIsBuyType(type);
   bool pending = (type != ORDER_TYPE_BUY && type != ORDER_TYPE_SELL);
   if(sl > 0.0 && ((buy && sl >= entry) || (!buy && sl <= entry)))
      return "Stop loss is on the wrong side of the entry";
   if(tp > 0.0 && ((buy && tp <= entry) || (!buy && tp >= entry)))
      return "Take profit is on the wrong side of the entry";
   // At least one point even when the broker sets no stops level: a buy's stop at or above the
   // bid (inside the spread) would be refused by the server.
   double minDist = MathMax((double)s.stopsLevel, 1.0) * s.point;
   double eps = s.point * 0.5;
   string minTxt = (s.stopsLevel > 0) ? " (broker minimum " + DoubleToString(AiSafeDiv(minDist, s.pipSize), 1) + " pips)" : "";
   if(pending)
     {
      double ref = buy ? ask : bid;
      if(MathAbs(entry - ref) < minDist - eps)
         return "Entry is too close to the market" + minTxt;
      if(sl > 0.0 && MathAbs(entry - sl) < minDist - eps)
         return "Stop loss is too close to the entry" + minTxt;
      if(tp > 0.0 && MathAbs(tp - entry) < minDist - eps)
         return "Take profit is too close to the entry" + minTxt;
      return "";
     }
   if(buy)
     {
      if(sl > 0.0 && bid - sl < minDist - eps)
         return "Stop loss is too close to the price" + minTxt;
      if(tp > 0.0 && tp - bid < minDist - eps)
         return "Take profit is too close to the price" + minTxt;
     }
   else
     {
      if(sl > 0.0 && sl - ask < minDist - eps)
         return "Stop loss is too close to the price" + minTxt;
      if(tp > 0.0 && ask - tp < minDist - eps)
         return "Take profit is too close to the price" + minTxt;
     }
   return "";
  }

// "" when the symbol accepts this order type with these levels.
string AiCheckTradeMode(const AiSpec &s, const ENUM_ORDER_TYPE type, const double sl, const double tp)
  {
   bool buy = AiIsBuyType(type);
   if(s.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      return "Trading is disabled on this symbol";
   if(s.tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return "This symbol is close-only";
   if(s.tradeMode == SYMBOL_TRADE_MODE_LONGONLY && !buy)
      return "This symbol allows buys only";
   if(s.tradeMode == SYMBOL_TRADE_MODE_SHORTONLY && buy)
      return "This symbol allows sells only";
   if(s.orderFlags == 0)
      return "";
   bool limit = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT);
   bool stop = (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP);
   if(!limit && !stop && (s.orderFlags & SYMBOL_ORDER_MARKET) == 0)
      return "Market orders are not allowed on this symbol";
   if(limit && (s.orderFlags & SYMBOL_ORDER_LIMIT) == 0)
      return "Limit orders are not allowed on this symbol";
   if(stop && (s.orderFlags & SYMBOL_ORDER_STOP) == 0)
      return "Stop orders are not allowed on this symbol";
   if(sl > 0.0 && (s.orderFlags & SYMBOL_ORDER_SL) == 0)
      return "This symbol does not accept a stop loss";
   if(tp > 0.0 && (s.orderFlags & SYMBOL_ORDER_TP) == 0)
      return "This symbol does not accept a take profit";
   return "";
  }

// Money lost by 1 lot from entry to the stop, in account currency. OrderCalcProfit handles
// cross rates, metals and indices; tick value is the fallback.
bool AiLossPerLot(const AiSpec &s, const int side, const double entry, const double sl, double &loss)
  {
   loss = 0.0;
   if(entry <= 0.0 || sl <= 0.0)
      return false;
   double profit = 0.0;
   ENUM_ORDER_TYPE t = (side == AI_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(t, s.symbol, 1.0, entry, sl, profit) && profit < 0.0)
     {
      loss = -profit;
      return true;
     }
   double tick = (s.tickSize > 0.0) ? s.tickSize : s.point;
   double tv = SymbolInfoDouble(s.symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0.0)
      tv = SymbolInfoDouble(s.symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick <= 0.0 || tv <= 0.0)
      return false;
   loss = MathAbs(entry - sl) / tick * tv;
   return loss > 0.0;
  }

// Money won by 1 lot from entry to exitPrice (on the profit side).
bool AiProfitPerLot(const AiSpec &s, const int side, const double entry, const double exitPrice, double &gain)
  {
   gain = 0.0;
   if(entry <= 0.0 || exitPrice <= 0.0)
      return false;
   double profit = 0.0;
   ENUM_ORDER_TYPE t = (side == AI_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(t, s.symbol, 1.0, entry, exitPrice, profit) && profit > 0.0)
     {
      gain = profit;
      return true;
     }
   double tick = (s.tickSize > 0.0) ? s.tickSize : s.point;
   double tv = SymbolInfoDouble(s.symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if(tv <= 0.0)
      tv = SymbolInfoDouble(s.symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick <= 0.0 || tv <= 0.0)
      return false;
   gain = MathAbs(exitPrice - entry) / tick * tv;
   return gain > 0.0;
  }

// Largest lot size that loses at most 'risk' at the stop, rounded down to the volume step.
// code tells why the answer is 0 (or that it was capped at the maximum lot).
double AiLotsForRisk(const double risk, const double lossPerLot, const double commRT, const AiSpec &s, int &code)
  {
   code = AI_LOTS_OK;
   double perLot = lossPerLot + MathMax(commRT, 0.0);
   if(risk <= 0.0)
     {
      code = AI_LOTS_NO_RISK;
      return 0.0;
     }
   if(perLot <= 0.0)
     {
      code = AI_LOTS_NO_VALUE;
      return 0.0;
     }
   double lots = AiFloorToStep(risk / perLot, s.volStep);
   if(lots < s.volMin - 1e-9)
     {
      code = AI_LOTS_BELOW_MIN;
      return 0.0;
     }
   if(s.volMax > 0.0 && lots > s.volMax + 1e-9)
     {
      code = AI_LOTS_CAPPED;
      lots = AiFloorToStep(s.volMax, s.volStep);
     }
   return lots;
  }

// Volume already open or pending on this symbol in one direction (for SYMBOL_VOLUME_LIMIT).
double AiOpenVolume(const string symbol, const int side)
  {
   double v = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      long pt = PositionGetInteger(POSITION_TYPE);
      if((side == AI_BUY && pt == POSITION_TYPE_BUY) || (side == AI_SELL && pt == POSITION_TYPE_SELL))
         v += PositionGetDouble(POSITION_VOLUME);
     }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
     {
      ulong ticket = OrderGetTicket(j);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      long ot = OrderGetInteger(ORDER_TYPE);
      bool ob = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY_STOP_LIMIT);
      bool os = (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP || ot == ORDER_TYPE_SELL_STOP_LIMIT);
      if((side == AI_BUY && ob) || (side == AI_SELL && os))
         v += OrderGetDouble(ORDER_VOLUME_CURRENT);
     }
   return v;
  }

// Builds the plan. Entry, SL and TP are filled even when a check fails, so the preview lines
// stay where the trader put them and can be dragged back.
void AiBuildPlan(const AiSpec &s, const AiInput &in, const AiSettings &cfg, const MqlTick &tick, AiPlan &p)
  {
   ZeroMemory(p);
   p.side = in.side;
   p.pending = in.pending;
   p.bid = tick.bid;
   p.ask = tick.ask;
   p.type = (in.side == AI_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!s.ok)
     {
      p.noData = true;
      p.err = "Loading " + s.symbol + " data from the broker...";
      return;
     }
   if(tick.bid <= 0.0 || tick.ask <= 0.0)
     {
      p.noData = true;
      p.err = "Waiting for " + s.symbol + " prices from the broker...";
      return;
     }
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   bool buy = (in.side == AI_BUY);
   p.spreadPips = AiSafeDiv(tick.ask - tick.bid, s.pipSize);
   p.base = (in.riskBase == AI_BASE_BALANCE) ? AccountInfoDouble(ACCOUNT_BALANCE) : AccountInfoDouble(ACCOUNT_EQUITY);

   // Entry and order type.
   p.entry = in.pending ? AiNormPrice(s, in.entry) : (buy ? tick.ask : tick.bid);
   if(p.entry <= 0.0)
     {
      p.err = "Set an entry price";
      return;
     }
   bool typeOk = true;
   p.type = AiResolveType(in.side, in.pending, p.entry, tick.bid, tick.ask, typeOk);

   // Stop loss.
   if(in.slValue > 0.0)
     {
      if(in.slMode == AI_LEVEL_PRICE)
         p.sl = AiNormPrice(s, in.slValue);
      else
         p.sl = AiNormPrice(s, p.entry - in.side * in.slValue * s.pipSize);
     }
   double slDist = (p.sl > 0.0) ? MathAbs(p.entry - p.sl) : 0.0;
   p.slPips = AiSafeDiv(slDist, s.pipSize);

   // Take profit.
   if(in.tpValue > 0.0)
     {
      if(in.tpMode == AI_LEVEL_PRICE)
         p.tp = AiNormPrice(s, in.tpValue);
      else if(in.tpMode == AI_LEVEL_RR)
         p.tp = (slDist > 0.0) ? AiNormPrice(s, p.entry + in.side * in.tpValue * slDist) : 0.0;
      else
         p.tp = AiNormPrice(s, p.entry + in.side * in.tpValue * s.pipSize);
     }
   double tpDist = (p.tp > 0.0) ? MathAbs(p.tp - p.entry) : 0.0;
   p.tpPips = AiSafeDiv(tpDist, s.pipSize);
   p.rr = AiSafeDiv(tpDist, slDist);

   if(!typeOk)
     {
      p.err = "Move the entry away from the market price";
      return;
     }
   if(p.sl > 0.0 && (buy ? p.sl >= p.entry : p.sl <= p.entry))
     {
      p.err = "Stop loss is on the wrong side of the entry";
      return;
     }
   if(p.tp > 0.0 && (buy ? p.tp <= p.entry : p.tp >= p.entry))
     {
      p.err = "Take profit is on the wrong side of the entry";
      return;
     }

   // Lot size.
   double lossPerLot = 0.0;
   bool haveLoss = (p.sl > 0.0) && AiLossPerLot(s, in.side, p.entry, p.sl, lossPerLot);
   double commRT = MathMax(cfg.commissionRT, 0.0);
   string lotErr = "";
   if(in.riskMode == AI_RISK_LOTS)
     {
      p.lots = AiFloorToStep(in.riskValue, s.volStep);
      if(p.lots < s.volMin - 1e-9)
        {
         lotErr = "Lot size is below the minimum " + AiLotsStr(s, s.volMin);
         p.lots = 0.0;
        }
      else if(s.volMax > 0.0 && p.lots > s.volMax + 1e-9)
        {
         p.lots = AiFloorToStep(s.volMax, s.volStep);
         p.warn = "Capped at the maximum lot " + AiLotsStr(s, p.lots);
        }
     }
   else
     {
      double target = (in.riskMode == AI_RISK_MONEY) ? in.riskValue : p.base * in.riskValue / 100.0;
      if(target <= 0.0)
         lotErr = "Set a risk above zero";
      else if(p.sl <= 0.0)
         lotErr = "Set a stop loss to size the trade";
      else if(!haveLoss)
         lotErr = "Cannot value the stop on this symbol";
      else
        {
         int code = AI_LOTS_OK;
         p.lots = AiLotsForRisk(target, lossPerLot, commRT, s, code);
         if(code == AI_LOTS_BELOW_MIN)
           {
            double minRisk = s.volMin * (lossPerLot + commRT);
            lotErr = "Min lot " + AiLotsStr(s, s.volMin) + " would risk " + AiMoney(minRisk, cur) +
                     " (" + DoubleToString(AiSafeDiv(minRisk, p.base) * 100.0, 2) + "%). Move the stop closer or raise the risk";
           }
         else if(code == AI_LOTS_CAPPED)
            p.warn = "Capped at the maximum lot " + AiLotsStr(s, p.lots);
         else if(code != AI_LOTS_OK)
            lotErr = "Cannot size this trade";
        }
     }
   if(p.lots > 0.0 && s.volLimit > 0.0)
     {
      double room = AiFloorToStep(s.volLimit - AiOpenVolume(s.symbol, in.side), s.volStep);
      if(room < s.volMin - 1e-9)
        {
         lotErr = "The symbol's volume limit is reached";
         p.lots = 0.0;
        }
      else if(p.lots > room)
        {
         p.lots = room;
         p.warn = "Reduced to the symbol's volume limit";
        }
     }

   // Money.
   if(p.lots > 0.0)
     {
      p.commission = commRT * p.lots;
      p.units = p.lots * s.contractSize;
      if(haveLoss)
         p.riskMoney = lossPerLot * p.lots + p.commission;
      double gainPerLot = 0.0;
      if(p.tp > 0.0 && AiProfitPerLot(s, in.side, p.entry, p.tp, gainPerLot))
         p.rewardMoney = gainPerLot * p.lots - p.commission;
      p.riskPct = AiSafeDiv(p.riskMoney, p.base) * 100.0;
      p.rewardPct = AiSafeDiv(p.rewardMoney, p.base) * 100.0;
      double tenPips = 0.0;
      if(AiProfitPerLot(s, in.side, p.entry, p.entry + in.side * 10.0 * s.pipSize, tenPips))
         p.pipValue = tenPips / 10.0 * p.lots;
      double margin = 0.0;
      if(OrderCalcMargin(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, s.symbol, p.lots, p.entry, margin))
         p.margin = margin;
      p.freeAfter = AccountInfoDouble(ACCOUNT_MARGIN_FREE) - p.margin;
     }

   // Checks, most basic first. The first problem is the one shown.
   if(lotErr != "")
     {
      p.err = lotErr;
      return;
     }
   if(cfg.requireSL && p.sl <= 0.0)
     {
      p.err = "Set a stop loss";
      return;
     }
   if(cfg.requireTP && p.tp <= 0.0)
     {
      p.err = "Set a take profit";
      return;
     }
   string stops = AiCheckStops(s, p.type, p.entry, p.sl, p.tp, tick.bid, tick.ask);
   if(stops != "")
     {
      p.err = stops;
      return;
     }
   string mode = AiCheckTradeMode(s, p.type, p.sl, p.tp);
   if(mode != "")
     {
      p.err = mode;
      return;
     }
   if(cfg.maxRiskPct > 0.0 && p.riskPct > cfg.maxRiskPct + 1e-9)
     {
      p.err = "Risk " + DoubleToString(p.riskPct, 2) + "% is above your " + AiTrimZeros(DoubleToString(cfg.maxRiskPct, 2)) + "% safety cap";
      return;
     }
   if(p.margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      p.err = "Not enough free margin: " + AiMoney(p.margin, cur) + " needed";
      return;
     }
   p.valid = true;
  }

//--- changes to open trades ---------------------------------------------

bool AiIsStopLimit(const ENUM_ORDER_TYPE type)
  {
   return (type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT);
  }

// Signed money for 'lots' from open to price: above 0 is a gain. OrderCalcProfit first, the tick
// value as the fallback, as in AiLossPerLot.
bool AiPnlAt(const AiSpec &s, const int side, const double lots, const double open, const double price, double &pnl)
  {
   pnl = 0.0;
   if(lots <= 0.0 || open <= 0.0 || price <= 0.0)
      return false;
   ENUM_ORDER_TYPE t = (side == AI_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(t, s.symbol, lots, open, price, pnl))
      return true;
   pnl = 0.0;
   double tick = (s.tickSize > 0.0) ? s.tickSize : s.point;
   double move = (price - open) * side;
   double tv = SymbolInfoDouble(s.symbol, (move < 0.0) ? SYMBOL_TRADE_TICK_VALUE_LOSS : SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if(tv <= 0.0)
      tv = SymbolInfoDouble(s.symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick <= 0.0 || tv <= 0.0)
      return false;
   pnl = move / tick * tv * lots;
   return true;
  }

// "" when the server should accept this change to an open trade, else why not.
// A position's SL and TP count from the market, not from its open price, so a stop at break-even
// or past it (locking in profit) is fine. A pending order must keep its type, and its levels count
// from its new entry. Nothing inside the broker's freeze level can change at all.
string AiCheckModify(const AiSpec &s, const AiLive &l, const double open, const double sl, const double tp, const double bid, const double ask)
  {
   if(AiIsStopLimit(l.type))
      return "Change a stop-limit order in MT5's Trade tab";
   if(s.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      return "Trading is disabled on this symbol";
   if(s.orderFlags != 0)
     {
      if(sl > 0.0 && (s.orderFlags & SYMBOL_ORDER_SL) == 0)
         return "This symbol does not accept a stop loss";
      if(tp > 0.0 && (s.orderFlags & SYMBOL_ORDER_TP) == 0)
         return "This symbol does not accept a take profit";
     }
   bool buy = (l.side == AI_BUY);
   double eps = s.point * 0.5;
   if(s.freezeLevel > 0)
     {
      double fz = s.freezeLevel * s.point;
      string fzTxt = "Too close to the market to change (broker freeze level " + DoubleToString(AiSafeDiv(fz, s.pipSize), 1) + " pips)";
      if(l.isOrder)
        {
         if(MathAbs(l.open - (buy ? ask : bid)) < fz - eps)
            return fzTxt;
        }
      else if(buy)
        {
         if((l.sl > 0.0 && bid - l.sl < fz - eps) || (l.tp > 0.0 && l.tp - bid < fz - eps))
            return fzTxt;
        }
      else if((l.sl > 0.0 && l.sl - ask < fz - eps) || (l.tp > 0.0 && ask - l.tp < fz - eps))
         return fzTxt;
     }
   if(l.isOrder)
     {
      bool okType = false;
      ENUM_ORDER_TYPE t = AiResolveType(l.side, true, open, bid, ask, okType);
      if(!okType || t != l.type)
        {
         bool below = (l.type == ORDER_TYPE_BUY_LIMIT || l.type == ORDER_TYPE_SELL_STOP);
         return "A " + AiOrderTypeName(l.type) + " must stay " + (below ? "below" : "above") + " the market price";
        }
      return AiCheckStops(s, l.type, open, sl, tp, bid, ask);
     }
   double minDist = MathMax((double)s.stopsLevel, 1.0) * s.point;
   string minTxt = (s.stopsLevel > 0) ? " (broker minimum " + DoubleToString(AiSafeDiv(minDist, s.pipSize), 1) + " pips)" : "";
   // A buy closes at the bid, a sell at the ask.
   double px = buy ? bid : ask;
   if(sl > 0.0 && (px - sl) * l.side < minDist - eps)
      return ((px - sl) * l.side <= 0.0) ? "Stop loss must stay " + (buy ? "below" : "above") + " the price" : "Stop loss is too close to the price" + minTxt;
   if(tp > 0.0 && (tp - px) * l.side < minDist - eps)
      return ((tp - px) * l.side <= 0.0) ? "Take profit must stay " + (buy ? "above" : "below") + " the price" : "Take profit is too close to the price" + minTxt;
   return "";
  }

// The safety cap blocks a change that takes the risk above it and makes it bigger. Tightening a
// stop, or adding one where there was none, always goes through.
bool AiModCapBlocks(const double cap, const double riskPct, const double newRisk, const double oldRisk, const bool hadStop)
  {
   if(cap <= 0.0 || riskPct <= cap + 1e-9 || !hadStop)
      return false;
   return (newRisk > oldRisk + 0.01);
  }

// Checks and values a change to an open trade. A position keeps its open price whatever 'open'
// says. base is the equity or balance the % is measured on.
void AiBuildModPlan(const AiSpec &s, const AiLive &l, const double open, const double sl, const double tp, const AiSettings &cfg,
                    const MqlTick &tick, const double base, AiModPlan &m)
  {
   ZeroMemory(m);
   m.open = l.isOrder ? AiNormPrice(s, open) : l.open;
   m.sl = AiNormPrice(s, sl);
   m.tp = AiNormPrice(s, tp);
   double eps = MathMax(s.point, 1e-10) * 0.5;
   m.changed = (MathAbs(m.open - l.open) > eps || MathAbs(m.sl - l.sl) > eps || MathAbs(m.tp - l.tp) > eps);
   if(!s.ok)
     {
      m.err = "Loading " + s.symbol + " data from the broker...";
      return;
     }
   if(tick.bid <= 0.0 || tick.ask <= 0.0)
     {
      m.err = "Waiting for " + s.symbol + " prices from the broker...";
      return;
     }
   double comm = MathMax(cfg.commissionRT, 0.0) * l.lots;
   double pnl = 0.0;
   if(m.sl > 0.0 && AiPnlAt(s, l.side, l.lots, m.open, m.sl, pnl))
      m.slMoney = pnl - comm;
   if(l.sl > 0.0 && AiPnlAt(s, l.side, l.lots, l.open, l.sl, pnl))
      m.oldSlMoney = pnl - comm;
   if(m.tp > 0.0 && AiPnlAt(s, l.side, l.lots, m.open, m.tp, pnl))
      m.tpMoney = pnl - comm;
   m.slPct = AiSafeDiv(m.slMoney, base) * 100.0;
   m.tpPct = AiSafeDiv(m.tpMoney, base) * 100.0;
   double slDist = (m.sl > 0.0) ? MathAbs(m.open - m.sl) : 0.0;
   double tpDist = (m.tp > 0.0) ? MathAbs(m.tp - m.open) : 0.0;
   m.slPips = AiSafeDiv(slDist, s.pipSize);
   m.tpPips = AiSafeDiv(tpDist, s.pipSize);
   if(m.sl > 0.0 && (m.sl - m.open) * l.side < 0.0)
      m.rr = AiSafeDiv(tpDist, slDist);

   // Checks, most basic first. The first problem is the one shown.
   if(cfg.requireSL && m.sl <= 0.0)
     {
      m.err = "Set a stop loss";
      return;
     }
   if(cfg.requireTP && m.tp <= 0.0)
     {
      m.err = "Set a take profit";
      return;
     }
   string chk = AiCheckModify(s, l, m.open, m.sl, m.tp, tick.bid, tick.ask);
   if(chk != "")
     {
      m.err = chk;
      return;
     }
   double riskPct = -m.slPct;
   if(m.sl > 0.0 && cfg.maxRiskPct > 0.0 && riskPct > cfg.maxRiskPct + 1e-9)
     {
      string capTxt = "Risk " + DoubleToString(riskPct, 2) + "% is above your " + AiTrimZeros(DoubleToString(cfg.maxRiskPct, 2)) + "% safety cap";
      if(AiModCapBlocks(cfg.maxRiskPct, riskPct, -m.slMoney, -m.oldSlMoney, l.sl > 0.0))
        {
         m.err = capTxt;
         return;
        }
      m.warn = capTxt;
     }
   m.valid = m.changed;
  }

#endif
