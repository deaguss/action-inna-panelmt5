//+------------------------------------------------------------------+
//| ActionInna - panel layout and drawing                            |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_PANEL_MQH
#define ACTIONINNA_PANEL_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "Ui.mqh"

// Everything the panel shows, already formatted by the app.
struct AiView
  {
   string            symbol;
   string            bid;
   string            ask;
   string            spread;
   int               phase;
   int               side;
   bool              pending;
   bool              compact;         // the slim layout: chosen by the trader, or forced by a short chart
   bool              forcedCompact;   // compact only because the chart is too short for the full panel
   bool              menuOpen;
   string            chipText[3];
   int               chip;            // 0..2 presets, 3 custom
   string            customText;
   string            customUnit;
   string            riskShort;       // the active risk in a few characters, for the compact layout
   string            riskLabel;
   string            slText;
   string            slUnit;
   string            tpText;
   string            tpUnit;
   string            entryText;
   string            entryType;
   string            lots;
   string            risk;
   string            reward;
   string            rr;
   string            pips;
   string            pipValue;
   string            margin;
   string            commission;
   bool              showCommission;
   string            confirmText;
   bool              confirmEnabled;
   bool              showCancel;      // X only appears when it has something to close
   string            status;
   int               statusLevel;     // 0 info, 1 warning, 2 error, 3 done
   bool              autoRecall;
   bool              oneClick;
   string            baseName;
   string            editing;         // edit field the trader is typing in
   bool              refreshEdits;    // values changed outside the edit fields
   int               focusCmd;        // control with keyboard focus (ENUM_AI_CMD), AI_CMD_NONE = none
  };

// Object names are AI_P_<TOKEN>#<part>. Clickable tokens map to commands; tokens starting with X
// are decoration.
class CAiPanel
  {
private:
   // Keyboard focus order: every control in visual order, with its rectangle for the focus ring.
   int               m_fCmd[];
   int               m_fx[];
   int               m_fy[];
   int               m_fw[];
   int               m_fh[];
   int               m_dragRight;     // the header moves the panel left of this x

   void              ClearFocusList()
     {
      ArrayResize(m_fCmd, 0);
      ArrayResize(m_fx, 0);
      ArrayResize(m_fy, 0);
      ArrayResize(m_fw, 0);
      ArrayResize(m_fh, 0);
     }

   void              AddFocus(const ENUM_AI_CMD cmd, const int fx, const int fy, const int fw, const int fh)
     {
      int n = ArraySize(m_fCmd);
      ArrayResize(m_fCmd, n + 1);
      ArrayResize(m_fx, n + 1);
      ArrayResize(m_fy, n + 1);
      ArrayResize(m_fw, n + 1);
      ArrayResize(m_fh, n + 1);
      m_fCmd[n] = (int)cmd;
      m_fx[n] = fx;
      m_fy[n] = fy;
      m_fw[n] = fw;
      m_fh[n] = fh;
     }

   // A button that is part of the focus order.
   void              Control(const ENUM_AI_CMD cmd, const string base, const int bx, const int by, const int bw, const int bh,
                             const string text, const color bg, const color border, const color txt, const int size, const bool bold, CAiUi &ui)
     {
      ui.Button(base, bx, by, bw, bh, text, bg, border, txt, size, bold);
      AddFocus(cmd, bx, by, bw, bh);
     }

   // Selected controls are neutral: text-coloured edge and bold text, so blue keeps meaning BUY.
   void              Choice(const ENUM_AI_CMD cmd, const string base, const int bx, const int by, const int bw, const int bh,
                            const string text, const bool on, const int size, const AiTheme &t, CAiUi &ui)
     {
      Control(cmd, base, bx, by, bw, bh, text, on ? t.selected : t.chip, on ? t.text : t.inputBorder, t.text, size, on, ui);
     }

   void              Wrap(const string text, const int maxW, const int fs, CAiUi &ui, string &l1, string &l2)
     {
      l1 = text;
      l2 = "";
      if(text == "" || ui.TextWidth(text, fs) <= maxW)
         return;
      string words[];
      int n = StringSplit(text, ' ', words);
      l1 = "";
      int i = 0;
      for(; i < n; i++)
        {
         string cand = (l1 == "") ? words[i] : l1 + " " + words[i];
         if(l1 != "" && ui.TextWidth(cand, fs) > maxW)
            break;
         l1 = cand;
        }
      for(; i < n; i++)
         l2 = (l2 == "") ? words[i] : l2 + " " + words[i];
      while(StringLen(l2) > 4 && ui.TextWidth(l2, fs) > maxW)
         l2 = StringSubstr(l2, 0, StringLen(l2) - 4) + "...";
     }

   void              LevelRow(const ENUM_AI_CMD modeCmd, const ENUM_AI_CMD lastCmd, const string key, const string label, const string text,
                              const string unit, const int cx, const int cy, const int lblW, const int fw, const int modeW, const int lastW,
                              const int gap, const int rowH, const AiView &v, const AiTheme &t, CAiUi &ui)
     {
      int fs = ui.fontSize;
      string edit = AI_P + "E_" + key;
      ui.Label(AI_P + "X" + key + "LBL#t", cx, cy + rowH / 2, label, t.text, fs, ANCHOR_LEFT, false);
      ui.Edit(edit, cx + lblW, cy, fw, rowH, text, t.text, t.inputBg, t.inputBorder, v.refreshEdits, v.editing);
      Control(modeCmd, AI_P + key + "MODE", cx + lblW + fw + gap, cy, modeW, rowH, unit, t.chip, t.inputBorder, t.text, fs - 1, false, ui);
      Control(lastCmd, AI_P + key + "LAST", cx + lblW + fw + modeW + 2 * gap, cy, lastW, rowH, "Last", t.chip, t.inputBorder, t.muted, fs - 1, false, ui);
     }

   int               Readout(const string key, const string label, const string value, const color vc, const int cx, const int cy,
                             const int cw, const int rh, const AiTheme &t, CAiUi &ui, const bool bold)
     {
      ui.Label(AI_P + "XR" + key + "#l", cx, cy, label, t.muted, ui.fontSize - 1, ANCHOR_LEFT_UPPER, false);
      ui.Label(AI_P + "XR" + key + "#v", cx + cw, cy, value, vc, ui.fontSize - 1, ANCHOR_RIGHT_UPPER, bold);
      return cy + rh;
     }

   // A whole-row toggle: a box that is filled when on, plus the words On/Off, so the state never
   // depends on colour alone.
   int               Toggle(const ENUM_AI_CMD cmd, const string key, const string label, const bool on, const int cx, const int cy, const int cw,
                            const AiTheme &t, CAiUi &ui)
     {
      int rh = ui.S(24);
      int box = ui.S(12);
      ui.Rect(AI_P + key + "#bg", cx, cy, cw, rh, t.bg, t.bg, 12);
      ui.Rect(AI_P + key + "#bx", cx, cy + (rh - box) / 2, box, box, on ? t.text : t.inputBg, on ? t.text : t.inputBorder, 13);
      ui.Label(AI_P + key + "#tx", cx + box + ui.S(8), cy + rh / 2, label, t.text, ui.fontSize - 1, ANCHOR_LEFT, false, 13);
      ui.Label(AI_P + key + "#st", cx + cw, cy + rh / 2, on ? "On" : "Off", t.muted, ui.fontSize - 1, ANCHOR_RIGHT, on, 13);
      AddFocus(cmd, cx, cy, cw, rh);
      return cy + rh;
     }

   // CONFIRM (and X when it can close something), then two status lines.
   int               ConfirmAndStatus(const AiView &v, const AiTheme &t, CAiUi &ui, const int cx, const int top, const int cw, const int gap, const bool showConfirm)
     {
      int fs = ui.fontSize;
      int cy = top;
      if(showConfirm)
        {
         int xw = ui.S(30);
         int ch2 = ui.S(32);
         int confW = v.showCancel ? cw - xw - gap : cw;
         color cbg = v.confirmEnabled ? ((v.side == AI_BUY) ? t.buyFill : t.sellFill) : t.chip;
         color cbd = v.confirmEnabled ? cbg : t.inputBorder;
         color ctx = v.confirmEnabled ? t.onFill : t.muted;
         Control(AI_CMD_CONFIRM, AI_P + "CONFIRM", cx, cy, confW, ch2, v.confirmText, cbg, cbd, ctx, fs, v.confirmEnabled, ui);
         if(v.showCancel)
            Control(AI_CMD_CANCEL, AI_P + "CANCEL", cx + confW + gap, cy, xw, ch2, "X", t.chip, t.inputBorder, t.text, fs, true, ui);
         cy += ch2 + ui.S(6);
        }
      color sc = t.muted;
      if(v.statusLevel == 1)
         sc = t.warn;
      else if(v.statusLevel == 2)
         sc = t.danger;
      else if(v.statusLevel == 3)
         sc = t.good;
      string l1 = "";
      string l2 = "";
      Wrap(v.status, cw, fs - 1, ui, l1, l2);
      ui.Label(AI_P + "XST1#t", cx, cy, l1, sc, fs - 1, ANCHOR_LEFT_UPPER, false);
      ui.Label(AI_P + "XST2#t", cx, cy + ui.S(15), l2, sc, fs - 1, ANCHOR_LEFT_UPPER, false);
      return cy + ui.S(34);
     }

   int               Menu(const AiView &v, const AiTheme &t, CAiUi &ui, const int cx, const int top, const int cw, const int gap, const int rowH)
     {
      int fs = ui.fontSize;
      int cy = top;
      ui.Rect(AI_P + "XDIV2#r", cx, cy, cw, 1, t.divider, t.divider, 11);
      cy += ui.S(6);
      cy = Toggle(AI_CMD_OPT_AUTO, "OPTAUTO", "Set SL/TP automatically", v.autoRecall, cx, cy, cw, t, ui);
      cy = Toggle(AI_CMD_OPT_ONECLICK, "OPTONE", "One-click trading (no preview)", v.oneClick, cx, cy, cw, t, ui);
      cy += gap;
      Control(AI_CMD_OPT_BASE, AI_P + "OPTBASE", cx, cy, cw, rowH, "Risk % is measured on: " + v.baseName, t.chip, t.inputBorder, t.text, fs - 1, false, ui);
      cy += rowH + gap;
      int hw = (cw - gap) / 2;
      Control(AI_CMD_PIN, AI_P + "PIN", cx, cy, hw, rowH, "Pin to new charts", t.chip, t.inputBorder, t.text, fs - 1, false, ui);
      Control(AI_CMD_TEMPLATE, AI_P + "SAVETPL", cx + hw + gap, cy, cw - hw - gap, rowH, "Save template", t.chip, t.inputBorder, t.text, fs - 1, false, ui);
      return cy + rowH + ui.S(8);
     }

   // Four bars around the focused control, in the text colour (above 3:1 on the panel in both themes).
   void              FocusRing(const int idx, const AiTheme &t, CAiUi &ui)
     {
      int th = MathMax(2, ui.S(2));
      int off = MathMax(1, ui.S(2));
      int fx = m_fx[idx] - off - th;
      int fy = m_fy[idx] - off - th;
      int fw = m_fw[idx] + 2 * (off + th);
      int fh = m_fh[idx] + 2 * (off + th);
      ui.Rect(AI_P + "XFOC#t", fx, fy, fw, th, t.text, t.text, 15);
      ui.Rect(AI_P + "XFOC#b", fx, fy + fh - th, fw, th, t.text, t.text, 15);
      ui.Rect(AI_P + "XFOC#l", fx, fy, th, fh, t.text, t.text, 15);
      ui.Rect(AI_P + "XFOC#r", fx + fw - th, fy, th, fh, t.text, t.text, 15);
     }

public:
   int               x;
   int               y;               // where the panel is drawn
   int               prefY;           // where the trader put it; y moves up only while the chart is too short
   int               w;
   int               h;
   int               fullH;           // height of the full layout, measured on its last render
   bool              docked;          // follows the right edge of the chart
   int               chartW;
   int               chartH;

                     CAiPanel() : m_dragRight(0), x(0), y(0), prefY(0), w(256), h(300), fullH(0), docked(true), chartW(800), chartH(600) {}

   void              Place(const int cw, const int ch, CAiUi &ui)
     {
      chartW = cw;
      chartH = ch;
      w = ui.S(256);
      if(fullH <= 0)
         fullH = ui.S(440);
      if(docked)
         x = cw - w - ui.S(10);
      Clamp(ui);
     }

   void              MoveTo(const int nx, const int ny, CAiUi &ui)
     {
      x = nx;
      prefY = ny;
      Clamp(ui);
     }

   void              Clamp(CAiUi &ui)
     {
      if(x > chartW - ui.S(60))
         x = chartW - ui.S(60);
      if(x < 0)
         x = 0;
      if(prefY < 0)
         prefY = 0;
      y = MathMax(0, MathMin(prefY, chartH - h));
     }

   // Whether the full layout fits the chart's height.
   bool              FullFits(CAiUi &ui) const
     {
      return (fullH + ui.S(8) <= chartH);
     }

   bool              Contains(const int px, const int py) const
     {
      return (px >= x && px < x + w && py >= y && py < y + h);
     }

   // The free part of the header, left of its buttons, moves the panel.
   bool              InHeader(const int px, const int py, CAiUi &ui) const
     {
      return (px >= x && px < m_dragRight && py >= y && py < y + ui.S(40));
     }

   int               FocusCount() const
     {
      return ArraySize(m_fCmd);
     }

   ENUM_AI_CMD       FocusCmd(const int i) const
     {
      if(i < 0 || i >= ArraySize(m_fCmd))
         return AI_CMD_NONE;
      return (ENUM_AI_CMD)m_fCmd[i];
     }

   int               FocusIndex(const int cmd) const
     {
      if(cmd == AI_CMD_NONE)
         return -1;
      int n = ArraySize(m_fCmd);
      for(int i = 0; i < n; i++)
         if(m_fCmd[i] == cmd)
            return i;
      return -1;
     }

   ENUM_AI_CMD       CmdFromName(const string name) const
     {
      int plen = StringLen(AI_P);
      if(StringFind(name, AI_P) != 0)
         return AI_CMD_NONE;
      int hash = StringFind(name, "#", plen);
      string token = (hash > 0) ? StringSubstr(name, plen, hash - plen) : StringSubstr(name, plen);
      if(token == "BUY" || token == "MBUY")
         return AI_CMD_BUY;
      if(token == "SELL" || token == "MSELL")
         return AI_CMD_SELL;
      if(token == "CONFIRM")
         return AI_CMD_CONFIRM;
      if(token == "CANCEL")
         return AI_CMD_CANCEL;
      if(token == "RISK1")
         return AI_CMD_RISK1;
      if(token == "RISK2")
         return AI_CMD_RISK2;
      if(token == "RISK3")
         return AI_CMD_RISK3;
      if(token == "RISKUNIT")
         return AI_CMD_RISK_UNIT;
      if(token == "MRISK")
         return AI_CMD_RISK_NEXT;
      if(token == "SLMODE")
         return AI_CMD_SL_MODE;
      if(token == "TPMODE")
         return AI_CMD_TP_MODE;
      if(token == "SLLAST")
         return AI_CMD_SL_RECALL;
      if(token == "TPLAST")
         return AI_CMD_TP_RECALL;
      if(token == "KIND")
         return AI_CMD_KIND;
      if(token == "MENU")
         return AI_CMD_MENU;
      if(token == "COLLAPSE")
         return AI_CMD_COLLAPSE;
      if(token == "OPTAUTO")
         return AI_CMD_OPT_AUTO;
      if(token == "OPTONE")
         return AI_CMD_OPT_ONECLICK;
      if(token == "OPTBASE")
         return AI_CMD_OPT_BASE;
      if(token == "PIN")
         return AI_CMD_PIN;
      if(token == "SAVETPL")
         return AI_CMD_TEMPLATE;
      return AI_CMD_NONE;
     }

   void              Render(const AiView &v, const AiTheme &t, CAiUi &ui)
     {
      ClearFocusList();
      int fs = ui.fontSize;
      int pad = ui.S(10);
      int gap = ui.S(4);
      int cx = x + pad;
      int cw = w - 2 * pad;
      int rowH = ui.S(24);

      // Background first: objects created after it are drawn on top of it.
      ui.Rect(AI_P + "XBG#r", x, y, w, MathMax(h, ui.S(40)), t.bg, t.border, 10);

      // Header, left to right: symbol, Market/Pending, menu, collapse. Buttons are 24x24 at least.
      int cy = y + ui.S(8);
      int hb = ui.S(24);
      int bw = ui.S(24);
      int kw = ui.S(64);
      int right = x + w - pad;
      int colX = right - bw;
      int menuX = v.forcedCompact ? right - bw : colX - gap - bw;
      int kindX = menuX - gap - kw;
      m_dragRight = kindX;
      Choice(AI_CMD_KIND, AI_P + "KIND", kindX, cy, kw, hb, v.pending ? "Pending" : "Market", v.pending, fs - 1, t, ui);
      Choice(AI_CMD_MENU, AI_P + "MENU", menuX, cy, bw, hb, "...", v.menuOpen, fs, t, ui);
      // While a short chart forces the slim layout there is nothing to expand, so no button.
      if(!v.forcedCompact)
         Control(AI_CMD_COLLAPSE, AI_P + "COLLAPSE", colX, cy, bw, hb, v.compact ? "+" : "-", t.chip, t.inputBorder, t.text, fs, true, ui);
      ui.Label(AI_P + "XSYM#t", cx, cy + hb / 2, ui.Fit(v.symbol, kindX - gap - cx, fs + 1, true), t.text, fs + 1, ANCHOR_LEFT, true);
      cy += hb + ui.S(8);

      if(v.compact)
        {
         int third = (cw - 2 * gap) / 3;
         int mh = ui.S(26);
         Control(AI_CMD_SELL, AI_P + "MSELL", cx, cy, third, mh, v.bid, t.sellFill, t.sellFill, t.onFill, fs - 1, true, ui);
         Control(AI_CMD_RISK_NEXT, AI_P + "MRISK", cx + third + gap, cy, third, mh, v.riskShort, t.chip, t.inputBorder, t.text, fs - 1, false, ui);
         Control(AI_CMD_BUY, AI_P + "MBUY", cx + 2 * (third + gap), cy, cw - 2 * (third + gap), mh, v.ask, t.buyFill, t.buyFill, t.onFill, fs - 1, true, ui);
         cy += mh + ui.S(8);
         cy = ConfirmAndStatus(v, t, ui, cx, cy, cw, gap, v.phase != AI_PHASE_IDLE);
         if(v.menuOpen)
            cy = Menu(v, t, ui, cx, cy, cw, gap, rowH);
         h = cy - y;
         ui.Rect(AI_P + "XBG#r", x, y, w, h, t.bg, t.border, 10);
         int fc = FocusIndex(v.focusCmd);
         if(fc >= 0)
            FocusRing(fc, t, ui);
         return;
        }

      // SELL / BUY with live prices. The side being previewed is filled.
      int half = (cw - ui.S(6)) / 2;
      int bh = ui.S(46);
      bool live = (v.phase != AI_PHASE_IDLE);
      bool sellOn = (live && v.side == AI_SELL);
      bool buyOn = (live && v.side == AI_BUY);
      color sellTx = sellOn ? t.onFill : t.sellText;
      color buyTx = buyOn ? t.onFill : t.buyText;
      ui.Rect(AI_P + "SELL#bg", cx, cy, half, bh, sellOn ? t.sellFill : t.sellDim, sellOn ? t.sellFill : t.sellEdge, 12);
      ui.Label(AI_P + "SELL#t1", cx + ui.S(8), cy + ui.S(6), "SELL", sellTx, fs - 1, ANCHOR_LEFT_UPPER, true);
      ui.Label(AI_P + "SELL#t2", cx + ui.S(8), cy + ui.S(20), v.bid, sellTx, fs + 4, ANCHOR_LEFT_UPPER, true);
      AddFocus(AI_CMD_SELL, cx, cy, half, bh);
      int bx2 = cx + half + ui.S(6);
      int bw2 = cw - half - ui.S(6);
      ui.Rect(AI_P + "BUY#bg", bx2, cy, bw2, bh, buyOn ? t.buyFill : t.buyDim, buyOn ? t.buyFill : t.buyEdge, 12);
      ui.Label(AI_P + "BUY#t1", bx2 + bw2 - ui.S(8), cy + ui.S(6), "BUY", buyTx, fs - 1, ANCHOR_RIGHT_UPPER, true);
      ui.Label(AI_P + "BUY#t2", bx2 + bw2 - ui.S(8), cy + ui.S(20), v.ask, buyTx, fs + 4, ANCHOR_RIGHT_UPPER, true);
      AddFocus(AI_CMD_BUY, bx2, cy, bw2, bh);
      cy += bh + ui.S(3);
      ui.Label(AI_P + "XSPREAD#t", x + w / 2, cy, v.spread, t.muted, fs - 1, ANCHOR_UPPER, false);
      cy += ui.S(17);

      // Risk: three presets, a custom value and its unit (%, money, lots).
      ui.Label(AI_P + "XRISKL#t", cx, cy, v.riskLabel, t.muted, fs - 1, ANCHOR_LEFT_UPPER, false);
      cy += ui.S(16);
      int chipW = ui.S(42);
      Choice(AI_CMD_RISK1, AI_P + "RISK1", cx, cy, chipW, rowH, v.chipText[0], v.chip == 0, fs - 1, t, ui);
      Choice(AI_CMD_RISK2, AI_P + "RISK2", cx + chipW + gap, cy, chipW, rowH, v.chipText[1], v.chip == 1, fs - 1, t, ui);
      Choice(AI_CMD_RISK3, AI_P + "RISK3", cx + 2 * (chipW + gap), cy, chipW, rowH, v.chipText[2], v.chip == 2, fs - 1, t, ui);
      int unitW = ui.S(34);
      int ex = cx + 3 * (chipW + gap);
      int ew = cx + cw - ex - unitW - gap;
      bool customOn = (v.chip == 3);
      ui.Edit(AI_P + "E_RISK", ex, cy, ew, rowH, v.customText, t.text, t.inputBg, customOn ? t.text : t.inputBorder, v.refreshEdits, v.editing);
      Choice(AI_CMD_RISK_UNIT, AI_P + "RISKUNIT", ex + ew + gap, cy, unitW, rowH, v.customUnit, customOn, fs - 1, t, ui);
      cy += rowH + ui.S(8);

      // Stop loss, take profit and (pending only) entry price.
      int lblW = ui.S(76);
      int modeW = ui.S(44);
      int lastW = ui.S(38);
      int fw = cw - lblW - modeW - lastW - 2 * gap;
      LevelRow(AI_CMD_SL_MODE, AI_CMD_SL_RECALL, "SL", "Stop loss", v.slText, v.slUnit, cx, cy, lblW, fw, modeW, lastW, gap, rowH, v, t, ui);
      cy += rowH + ui.S(6);
      LevelRow(AI_CMD_TP_MODE, AI_CMD_TP_RECALL, "TP", "Take profit", v.tpText, v.tpUnit, cx, cy, lblW, fw, modeW, lastW, gap, rowH, v, t, ui);
      cy += rowH + ui.S(6);
      if(v.pending)
        {
         ui.Label(AI_P + "XENL#t", cx, cy + rowH / 2, "Entry", t.text, fs, ANCHOR_LEFT, false);
         ui.Edit(AI_P + "E_ENTRY", cx + lblW, cy, fw, rowH, v.entryText, t.text, t.inputBg, t.inputBorder, v.refreshEdits, v.editing);
         ui.Label(AI_P + "XENT#t", cx + cw, cy + rowH / 2, v.entryType, t.muted, fs - 1, ANCHOR_RIGHT, true);
         cy += rowH + ui.S(6);
        }

      // What the order means in money.
      ui.Rect(AI_P + "XDIV1#r", cx, cy, cw, 1, t.divider, t.divider, 11);
      cy += ui.S(6);
      int rh = ui.S(17);
      cy = Readout("LOTS", "Lots", v.lots, t.text, cx, cy, cw, rh, t, ui, true);
      cy = Readout("RISK", "Risk", v.risk, t.danger, cx, cy, cw, rh, t, ui, true);
      cy = Readout("REWARD", "Reward", v.reward, t.good, cx, cy, cw, rh, t, ui, true);
      cy = Readout("RR", "Risk : reward", v.rr, t.text, cx, cy, cw, rh, t, ui, false);
      cy = Readout("PIPS", "Distance (pips)", v.pips, t.text, cx, cy, cw, rh, t, ui, false);
      cy = Readout("PIPV", "Pip value", v.pipValue, t.text, cx, cy, cw, rh, t, ui, false);
      cy = Readout("MARGIN", "Margin", v.margin, t.text, cx, cy, cw, rh, t, ui, false);
      if(v.showCommission)
         cy = Readout("COMM", "Commission", v.commission, t.muted, cx, cy, cw, rh, t, ui, false);
      cy += ui.S(4);

      cy = ConfirmAndStatus(v, t, ui, cx, cy, cw, gap, true);
      // Measured before the menu: an open menu may run past a short chart (the panel moves up),
      // but it must not push the panel into the compact layout.
      fullH = cy - y;
      if(v.menuOpen)
         cy = Menu(v, t, ui, cx, cy, cw, gap, rowH);

      h = cy - y;
      ui.Rect(AI_P + "XBG#r", x, y, w, h, t.bg, t.border, 10);
      int fi = FocusIndex(v.focusCmd);
      if(fi >= 0)
         FocusRing(fi, t, ui);
     }
  };

#endif
