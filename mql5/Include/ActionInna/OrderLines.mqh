//+------------------------------------------------------------------+
//| ActionInna - lines of open trades, changed only through the card |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_ORDERLINES_MQH
#define ACTIONINNA_ORDERLINES_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "SymbolSpec.mqh"
#include "RiskCalc.mqh"
#include "Ui.mqh"
#include "PreviewLines.mqh"

// Positions and pending orders on 'symbol'. Market orders still being filled are left out.
int AiReadLive(const string symbol, AiLive &out[])
  {
   ArrayResize(out, 0);
   int n = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      bool buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      AiLive l;
      ZeroMemory(l);
      l.ticket = ticket;
      l.isOrder = false;
      l.type = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      l.side = buy ? AI_BUY : AI_SELL;
      l.lots = PositionGetDouble(POSITION_VOLUME);
      l.open = PositionGetDouble(POSITION_PRICE_OPEN);
      l.sl = PositionGetDouble(POSITION_SL);
      l.tp = PositionGetDouble(POSITION_TP);
      l.profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      ArrayResize(out, n + 1, 16);
      out[n] = l;
      n++;
     }
   total = OrdersTotal();
   for(int j = 0; j < total; j++)
     {
      ulong ticket = OrderGetTicket(j);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY || t == ORDER_TYPE_SELL || t == ORDER_TYPE_CLOSE_BY)
         continue;
      bool buy = (t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_BUY_STOP_LIMIT);
      AiLive l;
      ZeroMemory(l);
      l.ticket = ticket;
      l.isOrder = true;
      l.type = t;
      l.side = buy ? AI_BUY : AI_SELL;
      l.lots = OrderGetDouble(ORDER_VOLUME_CURRENT);
      l.open = OrderGetDouble(ORDER_PRICE_OPEN);
      l.sl = OrderGetDouble(ORDER_SL);
      l.tp = OrderGetDouble(ORDER_TP);
      l.stopLimit = OrderGetDouble(ORDER_PRICE_STOPLIMIT);
      l.timeType = (int)OrderGetInteger(ORDER_TYPE_TIME);
      l.expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      ArrayResize(out, n + 1, 16);
      out[n] = l;
      n++;
     }
   return n;
  }

// One trade with objects on the chart, and the price last written to each of its lines.
struct AiTradeObjs
  {
   ulong             ticket;
   double            written[3]; // 0 entry, 1 SL, 2 TP
  };

// Draws every open trade on the symbol in place of MT5's own trade lines. Dragging one of these
// lines only moves the line: the app puts the change on its card, and nothing reaches the server
// until the trader confirms it there.
// Object names are AI_O<ticket>#<level><part>. The level is E, S or T. The part is empty for the
// line, g for the server's level while a change is open, and b / x for the tag's box and text.
class CAiOrderLines
  {
private:
   AiTradeObjs       m_objs[];
   ulong             m_dragTicket;   // trade whose line the trader is dragging, 0 when none
   int               m_dragWhich;
   double            m_tick;
   bool              m_created;      // this Sync created objects

   string            Base(const ulong ticket) const
     {
      return AI_O + IntegerToString((long)ticket) + "#";
     }

   string            LevelKey(const int which) const
     {
      if(which == 0)
         return "E";
      if(which == 1)
         return "S";
      return "T";
     }

   bool              Moved(const double now, const double before) const
     {
      return MathAbs(now - before) > m_tick * 0.5;
     }

   int               Slot(const ulong ticket)
     {
      int n = ArraySize(m_objs);
      for(int i = 0; i < n; i++)
         if(m_objs[i].ticket == ticket)
            return i;
      ArrayResize(m_objs, n + 1);
      m_objs[n].ticket = ticket;
      for(int k = 0; k < 3; k++)
         m_objs[n].written[k] = 0.0;
      return n;
     }

   void              Remove(const int i)
     {
      ObjectsDeleteAll(0, Base(m_objs[i].ticket));
      int n = ArraySize(m_objs);
      for(int k = i; k < n - 1; k++)
         m_objs[k] = m_objs[k + 1];
      ArrayResize(m_objs, n - 1);
     }

   // A level the trade no longer has: its line and tag go.
   void              DropLevel(const ulong ticket, const int which)
     {
      string n = Base(ticket) + LevelKey(which);
      ObjectDelete(0, n);
      ObjectDelete(0, n + "b");
      ObjectDelete(0, n + "x");
     }

   void              SetLine(const int k, const int which, const double price, const color clr, const bool movable, const string tip)
     {
      string n = Base(m_objs[k].ticket) + LevelKey(which);
      if(ObjectFind(0, n) < 0)
        {
         if(!ObjectCreate(0, n, OBJ_HLINE, 0, 0, price))
            return;
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, n, OBJPROP_BACK, false);
         ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, n, OBJPROP_ZORDER, 5);
         m_objs[k].written[which] = price;
         m_created = true;
        }
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, movable);
      // Kept selected so one drag moves it, without a double click first.
      ObjectSetInteger(0, n, OBJPROP_SELECTED, movable);
      bool dragging = (m_objs[k].ticket == m_dragTicket && which == m_dragWhich);
      if(!dragging && m_objs[k].written[which] != price)
        {
         ObjectSetDouble(0, n, OBJPROP_PRICE, price);
         m_objs[k].written[which] = price;
        }
     }

   // Where the level is on the server while a change to it is open. Drawn behind the candles, so it
   // never covers the panel.
   void              SetGhost(const ulong ticket, const int which, const double price, const color clr)
     {
      string n = Base(ticket) + LevelKey(which) + "g";
      if(price <= 0.0)
        {
         if(ObjectFind(0, n) >= 0)
            ObjectDelete(0, n);
         return;
        }
      if(ObjectFind(0, n) < 0)
        {
         if(!ObjectCreate(0, n, OBJ_HLINE, 0, 0, price))
            return;
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, n, OBJPROP_BACK, true);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
         ObjectSetString(0, n, OBJPROP_TOOLTIP, "The level as it is now. It stays here until you confirm the change");
        }
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetDouble(0, n, OBJPROP_PRICE, price);
     }

   void              SetTag(const ulong ticket, const int which, const double price, const string text, const color bg, const color fg,
                            const string tip, CAiUi &ui, const bool left, const int chartW, const int chartH)
     {
      string n = Base(ticket) + LevelKey(which);
      if(AiEnsureTag(n + "b", n + "x"))
         m_created = true;
      AiPlaceTag(n + "b", n + "x", price, text, bg, fg, ui, left, chartW, chartH);
      ObjectSetString(0, n + "b", OBJPROP_TOOLTIP, tip);
      ObjectSetString(0, n + "x", OBJPROP_TOOLTIP, tip);
     }

   // " (was 1.08250)" while a change moved the level, " (new)" for a level the trade did not have.
   string            Was(const bool edit, const double now, const double before, const AiSpec &s) const
     {
      if(!edit || !Moved(now, before))
         return "";
      return (before > 0.0) ? " (was " + AiPriceStr(s, before) + ")" : " (new)";
     }

   // "SL 1.08250 | -$100.00 (-1.00%)", the money left out when the level cannot be valued.
   string            LevelText(const string label, const double price, const string was, const bool valued, const double money,
                               const double base, const AiSpec &s, const string cur) const
     {
      string t = label + " " + AiPriceStr(s, price) + was;
      if(valued)
         t += " | " + AiMoney(money, cur, true) + " (" + AiSignedPct(AiSafeDiv(money, base) * 100.0) + ")";
      return t;
     }

   void              SyncOne(const AiLive &l, const bool edit, const AiModPlan &mp, const AiSpec &s, const AiTheme &th, const double base,
                             const double commRT, const bool left, const int chartW, const int chartH, CAiUi &ui, const string cur)
     {
      int k = Slot(l.ticket);
      bool movable = !AiIsStopLimit(l.type);
      double open = edit ? mp.open : l.open;
      double sl = edit ? mp.sl : l.sl;
      double tp = edit ? mp.tp : l.tp;
      string what = l.isOrder ? AiOrderTypeName(l.type) : ((l.side == AI_BUY) ? "BUY" : "SELL");
      string tagTip = movable ? "Click to change this trade, or drag its lines" : "Change a stop-limit order in MT5's Trade tab";

      // Entry: a pending order's moves, and takes SL and TP along; a position's stays.
      string entryTip = tagTip;
      if(movable && l.isOrder)
         entryTip = "Drag to move this order. SL and TP keep their distance. A pop-up asks before anything changes";
      else if(movable)
         entryTip = "Position #" + IntegerToString((long)l.ticket) + ": drag its SL or TP line, or click its tag";
      SetLine(k, 0, open, th.entryLine, l.isOrder && movable, entryTip);
      string entryText = what + " " + AiLotsStr(s, l.lots) + " @ " + AiPriceStr(s, open) + Was(edit && l.isOrder, open, l.open, s);
      if(!l.isOrder)
         entryText += " | " + AiMoney(l.profit, cur, true);
      SetTag(l.ticket, 0, open, entryText, th.entryTag, th.onFill, tagTip, ui, left, chartW, chartH);

      // Stop loss and take profit, valued from the entry as it would be after the change.
      double comm = MathMax(commRT, 0.0) * l.lots;
      double pnl = 0.0;
      if(sl > 0.0)
        {
         bool valued = edit || AiPnlAt(s, l.side, l.lots, open, sl, pnl);
         double money = edit ? mp.slMoney : pnl - comm;
         SetLine(k, 1, sl, th.slLine, movable, movable ? "Drag to move the stop loss. A pop-up asks before anything changes" : tagTip);
         SetTag(l.ticket, 1, sl, LevelText("SL", sl, Was(edit, sl, l.sl, s), valued, money, base, s, cur), th.slTag, th.onFill, tagTip, ui, left, chartW, chartH);
        }
      else
         DropLevel(l.ticket, 1);
      if(tp > 0.0)
        {
         bool valued = edit || AiPnlAt(s, l.side, l.lots, open, tp, pnl);
         double money = edit ? mp.tpMoney : pnl - comm;
         SetLine(k, 2, tp, th.tpLine, movable, movable ? "Drag to move the take profit. A pop-up asks before anything changes" : tagTip);
         SetTag(l.ticket, 2, tp, LevelText("TP", tp, Was(edit, tp, l.tp, s), valued, money, base, s, cur), th.tpTag, th.onFill, tagTip, ui, left, chartW, chartH);
        }
      else
         DropLevel(l.ticket, 2);

      SetGhost(l.ticket, 0, (edit && l.isOrder && Moved(open, l.open)) ? l.open : 0.0, th.muted);
      SetGhost(l.ticket, 1, (edit && Moved(sl, l.sl)) ? l.sl : 0.0, th.muted);
      SetGhost(l.ticket, 2, (edit && Moved(tp, l.tp)) ? l.tp : 0.0, th.muted);
     }

public:
                     CAiOrderLines() : m_dragTicket(0), m_dragWhich(-1), m_tick(0.0), m_created(false) {}

   // editTicket is the trade with a change open (mp holds it), 0 for none. Returns true when it
   // created objects: MT5 draws them over the panel until the panel is drawn again.
   bool              Sync(const AiLive &live[], const ulong editTicket, const AiModPlan &mp, const AiSpec &s, const AiTheme &th, const double base,
                          const double commRT, const bool left, const int chartW, const int chartH, CAiUi &ui, const string cur)
     {
      m_tick = (s.tickSize > 0.0) ? s.tickSize : s.point;
      m_created = false;
      int n = ArraySize(live);
      for(int i = ArraySize(m_objs) - 1; i >= 0; i--)
        {
         bool stillOpen = false;
         for(int j = 0; j < n && !stillOpen; j++)
            stillOpen = (live[j].ticket == m_objs[i].ticket);
         if(!stillOpen)
            Remove(i);
        }
      for(int j = 0; j < n; j++)
         SyncOne(live[j], live[j].ticket == editTicket, mp, s, th, base, commRT, left, chartW, chartH, ui, cur);
      return m_created;
     }

   // While the mouse button is down: the line whose price moved away from what we wrote.
   bool              DetectDrag(ulong &ticket, int &which, double &price)
     {
      int n = ArraySize(m_objs);
      for(int k = 0; k < n; k++)
         for(int i = 0; i < 3; i++)
           {
            string name = Base(m_objs[k].ticket) + LevelKey(i);
            if(m_objs[k].written[i] < 0.0 || ObjectFind(0, name) < 0 || ObjectGetInteger(0, name, OBJPROP_SELECTABLE) == 0)
               continue;
            double p = ObjectGetDouble(0, name, OBJPROP_PRICE);
            if(p <= 0.0 || MathAbs(p - m_objs[k].written[i]) <= m_tick * 0.5)
               continue;
            ticket = m_objs[k].ticket;
            which = i;
            price = p;
            m_dragTicket = ticket;
            m_dragWhich = i;
            return true;
           }
      return false;
     }

   // The drag is over, taken or not. Every line is written again on the next Sync, so a line the
   // app did not take (dropped while an order was being sent, say) does not stay where it was left.
   void              EndDrag()
     {
      m_dragTicket = 0;
      m_dragWhich = -1;
      int n = ArraySize(m_objs);
      for(int k = 0; k < n; k++)
         for(int i = 0; i < 3; i++)
            m_objs[k].written[i] = -1.0;
     }

   // Splits an object name into its trade and level. part is "" for a line, "b" or "x" for a tag.
   bool              Parse(const string name, ulong &ticket, int &which, string &part) const
     {
      int plen = StringLen(AI_O);
      if(StringFind(name, AI_O) != 0)
         return false;
      int hash = StringFind(name, "#", plen);
      if(hash <= plen || hash + 1 >= StringLen(name))
         return false;
      ticket = (ulong)StringToInteger(StringSubstr(name, plen, hash - plen));
      string key = StringSubstr(name, hash + 1, 1);
      which = (key == "E") ? 0 : ((key == "S") ? 1 : ((key == "T") ? 2 : -1));
      part = StringSubstr(name, hash + 2);
      return (ticket > 0 && which >= 0);
     }

   // Call after the objects were deleted from the chart.
   void              Forget()
     {
      ArrayResize(m_objs, 0);
      EndDrag();
     }

   void              Clear()
     {
      ObjectsDeleteAll(0, AI_O);
      Forget();
     }
  };

#endif
