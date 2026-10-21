//+------------------------------------------------------------------+
//| ActionInna - theme and chart-object helpers for the panel        |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_UI_MQH
#define ACTIONINNA_UI_MQH

#include "Defines.mqh"
#include "Util.mqh"

// Colour roles. Blue means BUY and red means SELL, nothing else; green is the take profit and
// success, amber a warning. Selection is neutral (text colour), so it never reads as a trade side.
// Every pair used for text meets 4.5:1 and every control edge 3:1 (see DESIGN.md).
struct AiTheme
  {
   bool              dark;
   color             bg;
   color             border;
   color             text;
   color             muted;
   color             inputBg;
   color             inputBorder;  // edges of fields and buttons, 3:1 against bg
   color             chip;
   color             selected;     // background of a selected chip or toggle
   color             buyFill;      // filled BUY button and buy tag, white text on it
   color             sellFill;
   color             buyEdge;      // border of the idle BUY button
   color             sellEdge;
   color             buyDim;       // idle BUY button background
   color             sellDim;
   color             buyText;      // BUY text on buyDim
   color             sellText;
   color             onFill;
   color             danger;
   color             warn;
   color             good;
   color             divider;
   color             slLine;       // chart lines stay bright so they show on any chart
   color             tpLine;
   color             entryLine;    // neutral for both sides; the tag names the side
   color             slTag;        // tag fills, white text on them
   color             tpTag;
   color             entryTag;
   color             zoneSl;
   color             zoneTp;
  };

// Blends two colours: t = 0 gives a, t = 1 gives b. MQL5 colours are stored as 0x00BBGGRR.
color AiMix(const color a, const color b, const double t)
  {
   uint ua = (uint)a;
   uint ub = (uint)b;
   int ar = (int)(ua & 0xFF);
   int ag = (int)((ua >> 8) & 0xFF);
   int ab = (int)((ua >> 16) & 0xFF);
   int br = (int)(ub & 0xFF);
   int bgr = (int)((ub >> 8) & 0xFF);
   int bb = (int)((ub >> 16) & 0xFF);
   int r = (int)MathRound(ar + (br - ar) * t);
   int g = (int)MathRound(ag + (bgr - ag) * t);
   int bl = (int)MathRound(ab + (bb - ab) * t);
   return (color)((uint)r | ((uint)g << 8) | ((uint)bl << 16));
  }

bool AiIsDark(const color c)
  {
   uint u = (uint)c;
   double lum = 0.299 * (double)(u & 0xFF) + 0.587 * (double)((u >> 8) & 0xFF) + 0.114 * (double)((u >> 16) & 0xFF);
   return lum < 128.0;
  }

void AiBuildTheme(const int mode, const color chartBg, AiTheme &t)
  {
   bool dark = (mode == AI_THEME_DARK) || (mode == AI_THEME_AUTO && AiIsDark(chartBg));
   t.dark = dark;
   // Measured contrast (WCAG 2.x) is noted where a pair carries text or marks a control edge.
   if(dark)
     {
      t.bg          = C'23,25,31';
      t.border      = C'52,56,66';
      t.text        = C'232,234,239';   // 14.6 on bg
      t.muted       = C'142,149,163';   // 5.8 on bg, 5.2 on chip
      t.inputBg     = C'33,36,44';
      t.inputBorder = C'104,110,124';   // 3.4 against bg
      t.chip        = C'33,36,44';
      t.selected    = C'52,57,70';      // text on it 9.6
      t.buyFill     = C'36,104,214';    // white on it 5.2
      t.sellFill    = C'200,48,62';     // white on it 5.3
      t.buyEdge     = C'49,131,255';
      t.sellEdge    = C'235,77,92';
      t.buyText     = C'115,170,255';   // 6.3 on buyDim
      t.sellText    = C'255,125,136';   // 6.2 on sellDim
      t.danger      = C'255,110,110';   // 6.5 on bg
      t.warn        = C'242,177,80';    // 9.4 on bg
      t.good        = C'72,200,125';    // 8.2 on bg
      t.divider     = C'44,48,57';
      t.slLine      = C'235,77,92';
      t.tpLine      = C'38,180,110';
      t.entryLine   = C'142,149,163';
      t.tpTag       = C'22,124,74';     // white on it 5.2
      t.entryTag    = C'82,88,102';     // white on it 7.1
      t.buyDim      = AiMix(t.bg, t.buyEdge, 0.14);
      t.sellDim     = AiMix(t.bg, t.sellEdge, 0.14);
     }
   else
     {
      t.bg          = C'255,255,255';
      t.border      = C'210,214,222';
      t.text        = C'28,31,38';      // 16.5 on bg
      t.muted       = C'100,107,120';   // 5.4 on bg, 5.0 on chip
      t.inputBg     = C'245,247,250';
      t.inputBorder = C'128,134,146';   // 3.7 against bg
      t.chip        = C'245,247,250';
      t.selected    = C'228,231,237';   // text on it 13.3
      t.buyFill     = C'20,98,212';     // white on it 5.6
      t.sellFill    = C'198,40,56';     // white on it 5.6
      t.buyEdge     = C'20,98,212';
      t.sellEdge    = C'198,40,56';
      t.buyText     = C'16,86,190';     // 5.7 on buyDim
      t.sellText    = C'176,30,46';     // 5.7 on sellDim
      t.danger      = C'196,36,48';     // 5.8 on bg
      t.warn        = C'150,90,0';      // 5.6 on bg
      t.good        = C'16,122,62';     // 5.4 on bg
      t.divider     = C'230,233,238';
      t.slLine      = C'222,52,68';
      t.tpLine      = C'20,150,85';
      t.entryLine   = C'100,107,120';
      t.tpTag       = C'18,120,68';     // white on it 5.5
      t.entryTag    = C'72,78,92';      // white on it 8.3
      t.buyDim      = AiMix(t.bg, t.buyFill, 0.12);
      t.sellDim     = AiMix(t.bg, t.sellFill, 0.12);
     }
   t.onFill = clrWhite;
   t.slTag = t.sellFill;
   t.zoneSl = AiMix(chartBg, t.slLine, 0.16);
   t.zoneTp = AiMix(chartBg, t.tpLine, 0.16);
  }

// Draws panel objects and remembers which ones the current frame used. Objects a frame does not
// use are hidden, not deleted: MT5 draws objects in creation order, so keeping them keeps the
// panel above the preview lines that were created before it.
class CAiUi
  {
private:
   string            m_names[];
   bool              m_used[];
   bool              m_shown[];

   int               Track(const string name)
     {
      int n = ArraySize(m_names);
      for(int i = 0; i < n; i++)
         if(m_names[i] == name)
           {
            m_used[i] = true;
            return i;
           }
      ArrayResize(m_names, n + 1);
      ArrayResize(m_used, n + 1);
      ArrayResize(m_shown, n + 1);
      m_names[n] = name;
      m_used[n] = true;
      m_shown[n] = true;
      return n;
     }

   void              Reveal(const int i, const string name)
     {
      if(!m_shown[i])
        {
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         m_shown[i] = true;
        }
     }

   // Fresh objects get an empty tooltip; otherwise hovering shows their internal name.
   void              NoTooltip(const string name)
     {
      ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
     }

public:
   double            scale;       // pixels: Windows display scale x panel scale input
   double            fontScale;   // fonts: the panel scale input only (Windows scales fonts itself)
   string            font;
   int               fontSize;

                     CAiUi() : scale(1.0), fontScale(1.0), font("Arial"), fontSize(9) {}

   int               S(const double px) const
     {
      return (int)MathRound(px * scale);
     }

   int               F(const int size) const
     {
      return (int)MathMax(6, MathRound(size * fontScale));
     }

   string            BoldFont() const
     {
      return font + " Bold";
     }

   void              BeginFrame()
     {
      int n = ArraySize(m_used);
      for(int i = 0; i < n; i++)
         m_used[i] = false;
     }

   void              EndFrame()
     {
      int n = ArraySize(m_names);
      for(int i = 0; i < n; i++)
         if(!m_used[i] && m_shown[i])
           {
            ObjectSetInteger(0, m_names[i], OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            m_shown[i] = false;
           }
     }

   // Call after the objects were deleted from the chart.
   void              Forget()
     {
      ArrayResize(m_names, 0);
      ArrayResize(m_used, 0);
      ArrayResize(m_shown, 0);
     }

   void              Rect(const string name, const int x, const int y, const int w, const int h, const color bg, const color border, const int z)
     {
      int i = Track(name);
      if(ObjectFind(0, name) < 0)
        {
         if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
            return;
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         NoTooltip(name);
         m_shown[i] = true;
        }
      Reveal(i, name);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, MathMax(w, 1));
      ObjectSetInteger(0, name, OBJPROP_YSIZE, MathMax(h, 1));
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, name, OBJPROP_COLOR, border);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, z);
     }

   void              Label(const string name, const int x, const int y, const string text, const color clr, const int size, const ENUM_ANCHOR_POINT anchor, const bool bold, const int z = 13)
     {
      int i = Track(name);
      if(ObjectFind(0, name) < 0)
        {
         if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
            return;
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         NoTooltip(name);
         m_shown[i] = true;
        }
      Reveal(i, name);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      // An empty OBJ_LABEL shows the word "Label".
      ObjectSetString(0, name, OBJPROP_TEXT, (text == "") ? " " : text);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? BoldFont() : font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, F(size));
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, z);
     }

   // refresh: the value changed outside the field. editing: the field the trader is typing in,
   // which is left completely alone so it keeps its focus and its half-typed text.
   void              Edit(const string name, const int x, const int y, const int w, const int h, const string text, const color txt, const color bg, const color border, const bool refresh, const string editing)
     {
      int i = Track(name);
      bool created = false;
      if(ObjectFind(0, name) < 0)
        {
         if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0))
            return;
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_READONLY, false);
         ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_RIGHT);
         NoTooltip(name);
         created = true;
         m_shown[i] = true;
        }
      Reveal(i, name);
      if(!created && name == editing)
         return;
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, MathMax(w, 1));
      ObjectSetInteger(0, name, OBJPROP_YSIZE, MathMax(h, 1));
      ObjectSetInteger(0, name, OBJPROP_COLOR, txt);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
      ObjectSetString(0, name, OBJPROP_FONT, font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, F(fontSize));
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 14);
      if(created || refresh)
         ObjectSetString(0, name, OBJPROP_TEXT, text);
     }

   // A flat button: a rectangle with centred text. Clicks on either part reach the same command.
   void              Button(const string base, const int x, const int y, const int w, const int h, const string text, const color bg, const color border, const color txt, const int size, const bool bold)
     {
      Rect(base + "#bg", x, y, w, h, bg, border, 12);
      Label(base + "#tx", x + w / 2, y + h / 2, text, txt, size, ANCHOR_CENTER, bold, 13);
     }

   int               TextWidth(const string text, const int size, const bool bold = false)
     {
      TextSetFont(font, -F(size) * 10, bold ? FW_BOLD : FW_NORMAL);
      uint w = 0;
      uint h = 0;
      if(TextGetSize(text, w, h) && w > 0)
         return (int)w;
      return (int)(StringLen(text) * size * 0.75 * scale);
     }

   // Shortens text with ".." until it fits maxW pixels (long broker symbol names).
   string            Fit(const string text, const int maxW, const int size, const bool bold = false)
     {
      if(maxW <= 0 || TextWidth(text, size, bold) <= maxW)
         return text;
      string s = text;
      while(StringLen(s) > 1 && TextWidth(s + "..", size, bold) > maxW)
         s = StringSubstr(s, 0, StringLen(s) - 1);
      return s + "..";
     }
  };

#endif
