//+------------------------------------------------------------------+
//| ActionInna - entry/SL/TP preview lines, zones and price tags     |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_PREVIEWLINES_MQH
#define ACTIONINNA_PREVIEWLINES_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "SymbolSpec.mqh"
#include "Ui.mqh"

class CAiLines
  {
private:
   double            m_set[3];   // price last written to each line: 0 entry, 1 SL, 2 TP
   int               m_drag;     // line the trader is dragging, -1 when none
   double            m_tick;

   string            LineName(const int i) const
     {
      if(i == 0)
         return AI_L + "ENTRY";
      if(i == 1)
         return AI_L + "SL";
      return AI_L + "TP";
     }

   void              Show(const string name, const bool on)
     {
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, on ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
     }

   void              SetLine(const int i, const double price, const color clr, const ENUM_LINE_STYLE style, const string tip)
     {
      string n = LineName(i);
      if(ObjectFind(0, n) < 0)
        {
         if(!ObjectCreate(0, n, OBJ_HLINE, 0, 0, price))
            return;
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, n, OBJPROP_BACK, false);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, n, OBJPROP_ZORDER, 5);
         m_set[i] = price;
        }
      Show(n, true);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, n, OBJPROP_STYLE, style);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
      // Kept selected so one drag moves it, without a double click first.
      ObjectSetInteger(0, n, OBJPROP_SELECTED, true);
      if(i != m_drag && m_set[i] != price)
        {
         ObjectSetDouble(0, n, OBJPROP_PRICE, price);
         m_set[i] = price;
        }
     }

   void              SetZone(const string n, const double p1, const double p2, const color clr)
     {
      datetime t0 = iTime(_Symbol, _Period, 0);
      int ps = PeriodSeconds(_Period);
      datetime ta = t0 - 12 * ps;
      datetime tb = t0 + 2 * ps;
      if(ObjectFind(0, n) < 0)
        {
         if(!ObjectCreate(0, n, OBJ_RECTANGLE, 0, ta, p1, tb, p2))
            return;
         ObjectSetInteger(0, n, OBJPROP_FILL, true);
         ObjectSetInteger(0, n, OBJPROP_BACK, true);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
        }
      Show(n, true);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, n, OBJPROP_TIME, 0, ta);
      ObjectSetDouble(0, n, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, n, OBJPROP_TIME, 1, tb);
      ObjectSetDouble(0, n, OBJPROP_PRICE, 1, p2);
     }

   void              EnsureTag(const string key)
     {
      string rn = AI_T + key + "#bg";
      string ln = AI_T + key + "#tx";
      if(ObjectFind(0, rn) < 0 && ObjectCreate(0, rn, OBJ_RECTANGLE_LABEL, 0, 0, 0))
        {
         ObjectSetInteger(0, rn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, rn, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, rn, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rn, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, rn, OBJPROP_ZORDER, 6);
         ObjectSetString(0, rn, OBJPROP_TOOLTIP, "\n");
        }
      if(ObjectFind(0, ln) < 0 && ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0))
        {
         ObjectSetInteger(0, ln, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, ln, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, ln, OBJPROP_ZORDER, 7);
         ObjectSetString(0, ln, OBJPROP_TOOLTIP, "\n");
        }
     }

   // Hidden lines are deselected too, so their handles do not linger on the chart.
   void              HideLine(const int i)
     {
      ObjectSetInteger(0, LineName(i), OBJPROP_SELECTED, false);
      Show(LineName(i), false);
     }

   void              HideTag(const string key)
     {
      Show(AI_T + key + "#bg", false);
      Show(AI_T + key + "#tx", false);
     }

   // A coloured price tag on the line. Off-screen levels stick to the edge with an arrow.
   void              SetTag(const string key, const double price, const string text, const color bg, const color fg, CAiUi &ui, const bool left, const int chartW, const int chartH)
     {
      EnsureTag(key);
      string rn = AI_T + key + "#bg";
      string ln = AI_T + key + "#tx";
      int x = 0;
      int y = 0;
      if(!ChartTimePriceToXY(0, 0, TimeCurrent(), price, x, y))
        {
         HideTag(key);
         return;
        }
      int fs = MathMax(ui.fontSize - 1, 7);
      int h = ui.S(18);
      int pad = ui.S(6);
      string shown = text;
      int ty = y - h / 2;
      if(y < 0)
        {
         shown = "^ " + text;
         ty = 0;
        }
      else if(y > chartH)
        {
         shown = "v " + text;
         ty = chartH - h;
        }
      ty = MathMax(0, MathMin(ty, chartH - h));
      int w = ui.TextWidth(shown, fs) + 2 * pad;
      int tx = left ? ui.S(8) : chartW - w - ui.S(8);
      Show(rn, true);
      Show(ln, true);
      ObjectSetInteger(0, rn, OBJPROP_XDISTANCE, tx);
      ObjectSetInteger(0, rn, OBJPROP_YDISTANCE, ty);
      ObjectSetInteger(0, rn, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, rn, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, rn, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, rn, OBJPROP_COLOR, bg);
      ObjectSetInteger(0, ln, OBJPROP_XDISTANCE, tx + pad);
      ObjectSetInteger(0, ln, OBJPROP_YDISTANCE, ty + h / 2);
      ObjectSetString(0, ln, OBJPROP_TEXT, shown);
      ObjectSetString(0, ln, OBJPROP_FONT, ui.font);
      ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, ui.F(fs));
      ObjectSetInteger(0, ln, OBJPROP_COLOR, fg);
     }

public:
                     CAiLines() : m_drag(-1), m_tick(0.0)
     {
      ArrayInitialize(m_set, 0.0);
     }

   // Creates every object hidden. Called before the panel is drawn, so the panel stays on top.
   void              Create(const double anyPrice)
     {
      m_drag = -1;
      for(int i = 0; i < 3; i++)
        {
         SetLine(i, anyPrice, clrGray, STYLE_SOLID, "");
         HideLine(i);
        }
      SetZone(AI_Z + "SL", anyPrice, anyPrice, clrGray);
      SetZone(AI_Z + "TP", anyPrice, anyPrice, clrGray);
      Show(AI_Z + "SL", false);
      Show(AI_Z + "TP", false);
      EnsureTag("ENTRY");
      EnsureTag("SL");
      EnsureTag("TP");
      HideTag("ENTRY");
      HideTag("SL");
      HideTag("TP");
     }

   void              HideAll()
     {
      for(int i = 0; i < 3; i++)
         HideLine(i);
      Show(AI_Z + "SL", false);
      Show(AI_Z + "TP", false);
      HideTag("ENTRY");
      HideTag("SL");
      HideTag("TP");
      m_drag = -1;
     }

   // 0 entry, 1 SL, 2 TP, -1 for any other object.
   int               IndexOf(const string name) const
     {
      for(int i = 0; i < 3; i++)
         if(name == LineName(i))
            return i;
      return -1;
     }

   // While the mouse button is down: the line whose price moved away from what we wrote.
   bool              DetectDrag(int &idx, double &price)
     {
      for(int i = 0; i < 3; i++)
        {
         string n = LineName(i);
         if(ObjectFind(0, n) < 0 || ObjectGetInteger(0, n, OBJPROP_TIMEFRAMES) == OBJ_NO_PERIODS)
            continue;
         double p = ObjectGetDouble(0, n, OBJPROP_PRICE);
         if(p <= 0.0)
            continue;
         if(MathAbs(p - m_set[i]) > m_tick * 0.5)
           {
            idx = i;
            price = p;
            m_drag = i;
            return true;
           }
        }
      return false;
     }

   void              EndDrag()
     {
      m_drag = -1;
     }

   void              Sync(const AiPlan &p, const AiSpec &s, const AiTheme &th, const bool show, const bool zones, const bool tagsLeft, const int chartW, const int chartH, CAiUi &ui, const string cur)
     {
      m_tick = (s.tickSize > 0.0) ? s.tickSize : s.point;
      if(!show || p.entry <= 0.0)
        {
         HideAll();
         return;
        }
      SetLine(0, p.entry, th.entryLine, STYLE_SOLID, p.pending ? "Drag to move the entry price" : "Drag to make this a pending order at that price");
      if(p.sl > 0.0)
         SetLine(1, p.sl, th.slLine, STYLE_DASH, "Drag to move the stop loss");
      else
         HideLine(1);
      if(p.tp > 0.0)
         SetLine(2, p.tp, th.tpLine, STYLE_DASH, "Drag to move the take profit");
      else
         HideLine(2);

      if(zones && p.sl > 0.0)
         SetZone(AI_Z + "SL", p.entry, p.sl, th.zoneSl);
      else
         Show(AI_Z + "SL", false);
      if(zones && p.tp > 0.0)
         SetZone(AI_Z + "TP", p.entry, p.tp, th.zoneTp);
      else
         Show(AI_Z + "TP", false);

      string lots = (p.lots > 0.0) ? AiLotsStr(s, p.lots) : "-";
      SetTag("ENTRY", p.entry, AiOrderTypeName(p.type) + " " + lots + " @ " + AiPriceStr(s, p.entry), th.entryTag, th.onFill, ui, tagsLeft, chartW, chartH);
      if(p.sl > 0.0)
        {
         string t1 = "SL " + AiPriceStr(s, p.sl) + " | " + DoubleToString(p.slPips, 1) + " pips";
         if(p.riskMoney > 0.0)
            t1 += " | " + AiMoney(-p.riskMoney, cur) + " (" + DoubleToString(p.riskPct, 2) + "%)";
         SetTag("SL", p.sl, t1, th.slTag, th.onFill, ui, tagsLeft, chartW, chartH);
        }
      else
         HideTag("SL");
      if(p.tp > 0.0)
        {
         string t2 = "TP " + AiPriceStr(s, p.tp) + " | " + DoubleToString(p.tpPips, 1) + " pips";
         if(p.lots > 0.0)
            t2 += " | " + AiMoney(p.rewardMoney, cur, true) + " (" + DoubleToString(p.rewardPct, 2) + "%)";
         if(p.rr > 0.0)
            t2 += " | 1:" + DoubleToString(p.rr, 2);
         SetTag("TP", p.tp, t2, th.tpTag, th.onFill, ui, tagsLeft, chartW, chartH);
        }
      else
         HideTag("TP");
     }
  };

#endif
