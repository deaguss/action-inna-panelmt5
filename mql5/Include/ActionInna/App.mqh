//+------------------------------------------------------------------+
//| ActionInna - the app: state, commands and chart events           |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_APP_MQH
#define ACTIONINNA_APP_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "SymbolSpec.mqh"
#include "RiskCalc.mqh"
#include "Memory.mqh"
#include "Ui.mqh"
#include "PreviewLines.mqh"
#include "OrderLines.mqh"
#include "Hotkeys.mqh"
#include "Executor.mqh"
#include "ChartGuard.mqh"
#include "Panel.mqh"

// Phases: IDLE (panel only) -> PREVIEW (lines on the chart, CONFIRM armed) -> SENDING -> COOLDOWN
// (ignores clicks and keys queued while OrderSend blocked) -> IDLE after a fill, PREVIEW after a
// failure. The object is a global of the EA, so it survives timeframe and symbol changes.
// Open trades are drawn by CAiOrderLines; dragging one of their lines opens the modify card, which
// works next to these phases and sends nothing until its own Confirm.
class CAiApp
  {
public:
   AiSettings        cfg;            // filled from the EA inputs before every Init()

private:
   AiSpec            m_spec;
   AiTheme           m_theme;
   AiPlan            m_plan;
   AiView            m_view;
   CAiUi             m_ui;
   CAiPanel          m_panel;
   CAiLines          m_lines;
   CAiOrderLines     m_orders;
   CAiExecutor       m_exec;
   CAiChartGuard     m_guard;
   CAiKv             m_store;
   AiKey             m_keys[AI_KEY_COUNT];
   AiMem             m_mem[];
   AiMem             m_hist;
   bool              m_histTried;
   bool              m_histFound;
   int               m_recallSL;
   int               m_recallTP;

   int               m_phase;
   int               m_afterCooldown;
   int               m_side;
   bool              m_pending;
   double            m_entry;
   bool              m_entryUserSet;  // the trader placed the entry (drag or typed), not the default
   string            m_defaultsSig;
   int               m_slMode;
   double            m_slValue;
   int               m_tpMode;
   double            m_tpValue;
   int               m_riskMode;
   double            m_riskValue;
   int               m_chip;
   int               m_customUnit;
   double            m_custom[3];
   int               m_riskBase;
   bool              m_autoRecall;
   bool              m_oneClick;
   bool              m_collapsed;     // the trader chose the slim layout
   bool              m_compact;       // the slim layout is shown (chosen, or the chart is too short)
   bool              m_forcedCompact; // shown slim only because the full panel does not fit
   bool              m_menuOpen;
   bool              m_refreshEdits;
   int               m_focusCmd;      // control with keyboard focus (Tab), AI_CMD_NONE when none

   string            m_status;
   int               m_statusLevel;
   ulong             m_statusUntil;  // 0 = until the next action
   string            m_permProblem;
   bool              m_netting;

   string            m_symbol;
   bool              m_inited;
   bool              m_tester;
   int               m_lastDeinit;
   ulong             m_cooldownUntil;
   ulong             m_previewSince;
   ulong             m_lastEndEdit;
   ulong             m_editingSince;
   string            m_editing;
   ulong             m_lastRefresh;
   ulong             m_lastPermCheck;
   string            m_lastSig;
   double            m_lastShift;

   bool              m_mouseDown;
   bool              m_dragPanel;
   int               m_dragDX;
   int               m_dragDY;
   bool              m_lineDrag;
   bool              m_orderDrag;    // the trader is dragging a line of an open trade
   ulong             m_lastMove;

   int               m_pinStep;
   string            m_pinName;

   // A change to an open trade: dragged or typed, shown on the card, sent only by its Confirm.
   AiLive            m_live[];       // positions and pending orders on the symbol, read on every refresh
   bool              m_modOn;
   bool              m_modDragging;  // its line is still under the mouse: the card opens on release
   AiLive            m_modLive;      // the trade as the server has it
   double            m_modOpen;
   double            m_modSl;
   double            m_modTp;
   int               m_modWhich;     // level moved last: 0 entry, 1 SL, 2 TP
   AiModPlan         m_mod;
   ulong             m_modSince;     // Confirm waits 300 ms after the card opened or its values moved
   int               m_modY;
   string            m_modStatus;
   int               m_modStatusLevel;
   bool              m_modSending;
   ulong             m_modBusyUntil; // clicks and keys queued while OrderSend blocked are ignored until then
   bool              m_raisePanel;   // trade objects were created over the panel: draw it again on top

   //--- small helpers --------------------------------------------------
   void              Status(const string text, const int level, const int ms)
     {
      m_status = text;
      m_statusLevel = level;
      m_statusUntil = (ms > 0) ? AiNowMs() + (ulong)ms : 0;
     }

   string            Currency() const
     {
      return AccountInfoString(ACCOUNT_CURRENCY);
     }

   // Equity or balance, whichever the risk % is measured on.
   double            RiskBaseMoney() const
     {
      return (m_riskBase == AI_BASE_BALANCE) ? AccountInfoDouble(ACCOUNT_BALANCE) : AccountInfoDouble(ACCOUNT_EQUITY);
     }

   // An order or a change is being sent, or was just sent: clicks and keys wait.
   bool              Busy() const
     {
      return (m_phase == AI_PHASE_SENDING || m_phase == AI_PHASE_COOLDOWN || m_modSending || AiNowMs() < m_modBusyUntil);
     }

   string            KeyHint() const
     {
      if(!cfg.hotkeys)
         return "Press SELL or BUY to preview the order";
      return "Keys: " + cfg.keyBuy + "/" + cfg.keySell + " preview, " + cfg.keyRisk1 + "-" + cfg.keyRisk3 +
             " risk, " + cfg.keyConfirm + " confirm, " + cfg.keyCancel + " cancel, " + cfg.keyRecall + " recall";
     }

   ENUM_AI_CMD       KeyCmd(const int slot) const
     {
      switch(slot)
        {
         case AI_KEY_BUY:
            return AI_CMD_BUY;
         case AI_KEY_SELL:
            return AI_CMD_SELL;
         case AI_KEY_CONFIRM:
            return AI_CMD_CONFIRM;
         case AI_KEY_CANCEL:
            return AI_CMD_CANCEL;
         case AI_KEY_RISK1:
            return AI_CMD_RISK1;
         case AI_KEY_RISK2:
            return AI_CMD_RISK2;
         case AI_KEY_RISK3:
            return AI_CMD_RISK3;
         case AI_KEY_RISKC:
            return AI_CMD_RISKC;
         case AI_KEY_RECALL:
            return AI_CMD_RECALL;
         case AI_KEY_PENDING:
            return AI_CMD_KIND;
         case AI_KEY_COLLAPSE:
            return AI_CMD_COLLAPSE;
        }
      return AI_CMD_NONE;
     }

   void              ParseKeys()
     {
      AiParseKey(cfg.keyBuy, m_keys[AI_KEY_BUY]);
      AiParseKey(cfg.keySell, m_keys[AI_KEY_SELL]);
      AiParseKey(cfg.keyConfirm, m_keys[AI_KEY_CONFIRM]);
      AiParseKey(cfg.keyCancel, m_keys[AI_KEY_CANCEL]);
      AiParseKey(cfg.keyRisk1, m_keys[AI_KEY_RISK1]);
      AiParseKey(cfg.keyRisk2, m_keys[AI_KEY_RISK2]);
      AiParseKey(cfg.keyRisk3, m_keys[AI_KEY_RISK3]);
      AiParseKey(cfg.keyRiskC, m_keys[AI_KEY_RISKC]);
      AiParseKey(cfg.keyRecall, m_keys[AI_KEY_RECALL]);
      AiParseKey(cfg.keyPending, m_keys[AI_KEY_PENDING]);
      AiParseKey(cfg.keyCollapse, m_keys[AI_KEY_COLLAPSE]);
     }

   //--- settings file --------------------------------------------------
   string            SettingsPath() const
     {
      return AI_FILES_DIR + "\\settings.txt";
     }

   // An input changed since the last run wins over the value saved from the panel.
   void              LoadSettings()
     {
      m_store.Load(SettingsPath());
      m_chip = (int)m_store.GetI("chip", 0);
      if(m_chip < 0 || m_chip > 3)
         m_chip = 0;
      m_customUnit = (int)m_store.GetI("unit", AI_RISK_PERCENT);
      if(m_customUnit < AI_RISK_PERCENT || m_customUnit > AI_RISK_LOTS)
         m_customUnit = AI_RISK_PERCENT;
      m_custom[AI_RISK_PERCENT] = m_store.GetD("c_pct", 0.5);
      m_custom[AI_RISK_MONEY] = m_store.GetD("c_money", 50.0);
      m_custom[AI_RISK_LOTS] = m_store.GetD("c_lots", 0.0);
      bool autoThen = m_store.GetB("auto_input", cfg.autoRecall);
      m_autoRecall = (autoThen != cfg.autoRecall) ? cfg.autoRecall : m_store.GetB("auto", cfg.autoRecall);
      int baseThen = (int)m_store.GetI("base_input", (long)cfg.riskBase);
      m_riskBase = (baseThen != (int)cfg.riskBase) ? (int)cfg.riskBase : (int)m_store.GetI("base", (long)cfg.riskBase);
      if(m_riskBase != AI_BASE_EQUITY && m_riskBase != AI_BASE_BALANCE)
         m_riskBase = AI_BASE_EQUITY;
      m_collapsed = m_store.GetB("collapsed", false);
      m_panel.docked = m_store.GetB("docked", true);
      m_panel.x = (int)m_store.GetI("px", 0);
      m_panel.prefY = (int)m_store.GetI("py", 0);
     }

   void              SaveSettings()
     {
      if(m_tester || !m_inited)
         return;
      m_store.Set("chip", IntegerToString(m_chip));
      m_store.Set("unit", IntegerToString(m_customUnit));
      m_store.Set("c_pct", DoubleToString(m_custom[AI_RISK_PERCENT], 4));
      m_store.Set("c_money", DoubleToString(m_custom[AI_RISK_MONEY], 2));
      m_store.Set("c_lots", DoubleToString(m_custom[AI_RISK_LOTS], 4));
      m_store.Set("auto", m_autoRecall ? "1" : "0");
      m_store.Set("auto_input", cfg.autoRecall ? "1" : "0");
      m_store.Set("base", IntegerToString(m_riskBase));
      m_store.Set("base_input", IntegerToString((int)cfg.riskBase));
      m_store.Set("collapsed", m_collapsed ? "1" : "0");
      m_store.Set("docked", m_panel.docked ? "1" : "0");
      m_store.Set("px", IntegerToString(m_panel.x));
      m_store.Set("py", IntegerToString(m_panel.prefY));
      m_store.Save(SettingsPath());
     }

   //--- levels and recall ---------------------------------------------
   string            DefaultsSig() const
     {
      return DoubleToString(cfg.defaultSLPips, 4) + "|" + IntegerToString((int)cfg.defaultTPMode) + "|" +
             DoubleToString(cfg.defaultTPValue, 4) + "|" + IntegerToString((int)cfg.pipMode);
     }

   // A new pending order starts as a limit order a little away from the market.
   double            DefaultPendingEntry(const int side) const
     {
      MqlTick t;
      if(!SymbolInfoTick(_Symbol, t) || t.bid <= 0.0)
         return 0.0;
      double market = (side == AI_SELL) ? t.bid : t.ask;
      return AiNormPrice(m_spec, market - side * MathMax(cfg.pendingOffsetPips, 0.0) * m_spec.pipSize);
     }

   void              DefaultLevels()
     {
      m_slMode = AI_LEVEL_PIPS;
      m_slValue = MathMax(cfg.defaultSLPips, 0.0);
      m_tpMode = (int)cfg.defaultTPMode;
      m_tpValue = MathMax(cfg.defaultTPValue, 0.0);
      if(m_tpMode == AI_LEVEL_PRICE)
        {
         // A fixed price makes no sense as a default for every symbol.
         m_tpMode = AI_LEVEL_RR;
         m_tpValue = 2.0;
        }
      m_entry = 0.0;
      m_entryUserSet = false;
      m_recallSL = 0;
      m_recallTP = 0;
      m_refreshEdits = true;
     }

   void              ReloadMemory()
     {
      AiMemLoad(_Symbol, m_mem);
     }

   bool              HistoryMem(AiMem &m)
     {
      if(!m_histTried)
        {
         m_histTried = true;
         m_histFound = AiMemFromHistory(_Symbol, m_hist);
        }
      if(!m_histFound)
         return false;
      m = m_hist;
      return true;
     }

   double            CurrentEntry() const
     {
      if(m_pending && m_entry > 0.0)
         return m_entry;
      MqlTick t;
      if(!SymbolInfoTick(_Symbol, t))
         return 0.0;
      return (m_side == AI_BUY) ? t.ask : t.bid;
     }

   // A remembered price level is reused only if it still sits on the right side of the entry.
   bool              LevelFits(const double price, const bool isStop, const double entry) const
     {
      if(price <= 0.0 || entry <= 0.0)
         return false;
      double d = (price - entry) * m_side;
      if(isStop)
         d = -d;
      double minDist = MathMax((double)m_spec.stopsLevel, 1.0) * m_spec.point;
      return d >= minDist;
     }

   // Restores SL and/or TP from record idx, in the mode they were set last time. A price level
   // that no longer fits falls back to the same distance.
   bool              ApplyRecall(const int idx, const bool doSL, const bool doTP, string &desc)
     {
      desc = "";
      AiMem m;
      ZeroMemory(m);
      int n = ArraySize(m_mem);
      if(n > 0)
        {
         int i = idx % n;
         if(i < 0)
            i = 0;
         m = m_mem[i];
        }
      else if(!HistoryMem(m))
         return false;
      double entry = CurrentEntry();
      // Distances are stored as price, so they convert to this symbol's pips whatever the broker.
      double pip = (m_spec.pipSize > 0.0) ? m_spec.pipSize : 1.0;
      if(doSL && m.slDist > 0.0)
        {
         if(m.slMode == AI_LEVEL_PRICE && LevelFits(m.slPrice, true, entry))
           {
            m_slMode = AI_LEVEL_PRICE;
            m_slValue = m.slPrice;
            desc += "SL " + AiPriceStr(m_spec, m_slValue);
           }
         else
           {
            m_slMode = AI_LEVEL_PIPS;
            m_slValue = NormalizeDouble(m.slDist / pip, 1);
            desc += "SL " + AiTrimZeros(DoubleToString(m_slValue, 1)) + " pips";
           }
        }
      if(doTP && (m.tpDist > 0.0 || m.tpR > 0.0))
        {
         string part = "";
         if(m.tpMode == AI_LEVEL_PRICE && LevelFits(m.tpPrice, false, entry))
           {
            m_tpMode = AI_LEVEL_PRICE;
            m_tpValue = m.tpPrice;
            part = "TP " + AiPriceStr(m_spec, m_tpValue);
           }
         else if(m.tpMode == AI_LEVEL_RR && m.tpR > 0.0)
           {
            m_tpMode = AI_LEVEL_RR;
            m_tpValue = NormalizeDouble(m.tpR, 2);
            part = "TP " + AiTrimZeros(DoubleToString(m_tpValue, 2)) + "R";
           }
         else if(m.tpDist > 0.0)
           {
            m_tpMode = AI_LEVEL_PIPS;
            m_tpValue = NormalizeDouble(m.tpDist / pip, 1);
            part = "TP " + AiTrimZeros(DoubleToString(m_tpValue, 1)) + " pips";
           }
         if(part != "")
            desc += (desc == "") ? part : ", " + part;
        }
      m_refreshEdits = true;
      return (desc != "");
     }

   // "Last" buttons and the recall key: each press steps one record further back. Records that
   // hold nothing for the requested level (a TP-only record for "SL Last") are skipped.
   void              RecallLevel(const bool doSL, const bool doTP)
     {
      ReloadMemory();
      int n = ArraySize(m_mem);
      int start = doSL ? m_recallSL : m_recallTP;
      string desc = "";
      int hit = -1;
      int tries = (n > 0) ? n : 1;
      for(int k = 0; k < tries; k++)
        {
         int idx = (n > 0) ? (start + k) % n : 0;
         if(ApplyRecall(idx, doSL, doTP, desc))
           {
            hit = idx;
            break;
           }
        }
      if(hit < 0)
        {
         string what = (doSL && doTP) ? "SL/TP" : (doSL ? "stop loss" : "take profit");
         Status("No earlier " + what + " saved for " + _Symbol, 0, 4000);
         return;
        }
      int next = (n > 0) ? (hit + 1) % n : 0;
      if(doSL)
         m_recallSL = next;
      if(doTP)
         m_recallTP = next;
      string from = (n > 0) ? "Recalled " + IntegerToString(hit + 1) + "/" + IntegerToString(n) : "From your last trade";
      Status(from + ": " + desc, 0, 5000);
     }

   void              SaveMemory()
     {
      if(m_plan.entry <= 0.0)
         return;
      AiMem m;
      ZeroMemory(m);
      m.t = (long)TimeCurrent();
      m.side = m_side;
      m.slMode = m_slMode;
      m.tpMode = m_tpMode;
      if(m_plan.sl > 0.0)
        {
         m.slPrice = m_plan.sl;
         m.slDist = MathAbs(m_plan.entry - m_plan.sl);
        }
      if(m_plan.tp > 0.0)
        {
         m.tpPrice = m_plan.tp;
         m.tpDist = MathAbs(m_plan.tp - m_plan.entry);
        }
      m.tpR = (m_tpMode == AI_LEVEL_RR) ? m_tpValue : m_plan.rr;
      if(m.slDist <= 0.0 && m.tpDist <= 0.0)
         return;
      ReloadMemory();
      AiMemPush(m_mem, m);
      if(!AiMemSave(_Symbol, m_mem))
         AiLog("Could not save the SL/TP memory file");
      m_recallSL = 0;
      m_recallTP = 0;
     }

   //--- commands -------------------------------------------------------
   // The active risk in a few characters: "1.5%", "$50", "0.10 lot".
   string            RiskShort() const
     {
      if(m_chip >= 0 && m_chip < 3)
         return AiTrimZeros(DoubleToString(cfg.preset[m_chip], 2)) + "%";
      double cv = m_custom[m_customUnit];
      string cur = Currency();
      if(m_customUnit == AI_RISK_PERCENT)
         return AiTrimZeros(DoubleToString(cv, 2)) + "%";
      if(m_customUnit == AI_RISK_MONEY)
         return AiMoney(cv, cur, false, (cv >= 100.0) ? 0 : 2);
      return AiLotsStr(m_spec, cv) + " lot";
     }

   void              SetChip(const int i)
     {
      if(i >= 0 && i < 3)
        {
         m_chip = i;
         m_riskMode = AI_RISK_PERCENT;
         m_riskValue = cfg.preset[i];
        }
      else
        {
         m_chip = 3;
         m_riskMode = m_customUnit;
         m_riskValue = m_custom[m_customUnit];
        }
     }

   void              CycleUnit()
     {
      m_customUnit = (m_customUnit + 1) % 3;
      if(m_customUnit == AI_RISK_LOTS && m_custom[AI_RISK_LOTS] <= 0.0)
         m_custom[AI_RISK_LOTS] = m_spec.volMin;
      SetChip(3);
      m_refreshEdits = true;
      SaveSettings();
     }

   // pips <-> price, keeping the line where it is.
   void              CycleSLMode()
     {
      if(m_slMode == AI_LEVEL_PIPS)
        {
         m_slMode = AI_LEVEL_PRICE;
         m_slValue = (m_plan.sl > 0.0) ? m_plan.sl : 0.0;
        }
      else
        {
         m_slMode = AI_LEVEL_PIPS;
         m_slValue = (m_plan.sl > 0.0) ? NormalizeDouble(m_plan.slPips, 1) : MathMax(cfg.defaultSLPips, 0.0);
        }
      m_refreshEdits = true;
     }

   // R -> pips -> price -> R, keeping the line where it is.
   void              CycleTPMode()
     {
      int next = AI_LEVEL_RR;
      if(m_tpMode == AI_LEVEL_RR)
         next = AI_LEVEL_PIPS;
      else if(m_tpMode == AI_LEVEL_PIPS)
         next = AI_LEVEL_PRICE;
      double value = 0.0;
      if(m_plan.tp > 0.0)
        {
         if(next == AI_LEVEL_PIPS)
            value = NormalizeDouble(m_plan.tpPips, 1);
         else if(next == AI_LEVEL_PRICE)
            value = m_plan.tp;
         else
            value = (m_plan.rr > 0.0) ? NormalizeDouble(m_plan.rr, 2) : 2.0;
        }
      else if(next == AI_LEVEL_RR)
         value = 2.0;
      m_tpMode = next;
      m_tpValue = value;
      m_refreshEdits = true;
     }

   void              TogglePending()
     {
      m_pending = !m_pending;
      if(m_pending)
        {
         m_entry = DefaultPendingEntry(m_side);
         m_entryUserSet = false;
        }
      m_refreshEdits = true;
     }

   void              ToggleOneClick()
     {
      if(!m_oneClick)
        {
         // OK/Cancel rather than Yes/No: Esc closes it.
         int answer = MessageBox("One-click trading sends the order as soon as you press SELL or BUY (or their keys), with no preview.\n\nPress OK to turn it on.",
                                 AI_NAME, MB_OKCANCEL | MB_ICONEXCLAMATION);
         if(answer != IDOK)
            return;
        }
      m_oneClick = !m_oneClick;
      Status(m_oneClick ? "One-click trading is on: SELL/BUY send at once" : "One-click trading is off", m_oneClick ? 1 : 0, 5000);
     }

   // Switching side during a preview keeps the distances: a price level for the other side
   // would sit on the wrong side.
   void              MirrorLevels()
     {
      if(m_slMode == AI_LEVEL_PRICE && m_plan.sl > 0.0)
        {
         m_slMode = AI_LEVEL_PIPS;
         m_slValue = NormalizeDouble(m_plan.slPips, 1);
        }
      if(m_tpMode == AI_LEVEL_PRICE && m_plan.tp > 0.0)
        {
         m_tpMode = AI_LEVEL_PIPS;
         m_tpValue = NormalizeDouble(m_plan.tpPips, 1);
        }
      m_refreshEdits = true;
     }

   void              OnSide(const int side)
     {
      m_collapsed = false;
      if(m_phase == AI_PHASE_PREVIEW && m_side == side)
        {
         Cancel();
         return;
        }
      bool fresh = (m_phase == AI_PHASE_IDLE);
      if(m_side != side)
        {
         // m_plan still describes the old side here (it is rebuilt on every refresh, idle too).
         MirrorLevels();
         if(m_pending && !m_entryUserSet)
            m_entry = DefaultPendingEntry(side);
        }
      m_side = side;
      if(fresh)
        {
         ReloadMemory();
         m_recallSL = 0;
         m_recallTP = 0;
         if(m_autoRecall)
           {
            string desc = "";
            if(ApplyRecall(0, true, true, desc))
              {
               m_recallSL = 1;
               m_recallTP = 1;
               Status("Set automatically: " + desc, 0, 4000);
              }
           }
        }
      m_phase = AI_PHASE_PREVIEW;
      m_previewSince = AiNowMs();
      if(m_oneClick && fresh)
        {
         Rebuild();
         if(m_plan.valid)
            Send();
         else
            Status(m_plan.err, 2, 0);
        }
     }

   void              Cancel()
     {
      m_menuOpen = false;
      if(m_phase == AI_PHASE_PREVIEW)
        {
         m_phase = AI_PHASE_IDLE;
         Status("Preview closed. Nothing was sent", 0, 2500);
        }
     }

   void              Confirm()
     {
      if(m_phase != AI_PHASE_PREVIEW)
        {
         Status("Press SELL or BUY first: the order is previewed on the chart before it can be confirmed", 0, 4000);
         return;
        }
      if(!m_plan.valid)
        {
         Status(m_plan.err, 2, 4000);
         return;
        }
      if(AiNowMs() - m_previewSince < 300)
         return;
      Send();
     }

   void              Send()
     {
      string perm = m_exec.PermissionProblem();
      if(perm != "")
        {
         m_permProblem = perm;
         Status(perm, 2, 0);
         return;
        }
      double seenRisk = m_plan.riskMoney;
      // The timer reloads symbol data once a second; the checks before sending use the newest.
      AiLoadSpec(_Symbol, (int)cfg.pipMode, m_spec);
      m_phase = AI_PHASE_SENDING;
      Draw(true);   // show "Sending..." before OrderSend blocks
      AiSendResult r;
      ZeroMemory(r);
      for(int attempt = 0; attempt < 3; attempt++)
        {
         Rebuild();   // freshest price
         if(!m_plan.valid)
           {
            m_phase = AI_PHASE_PREVIEW;
            Status(m_plan.err, 2, 0);
            return;
           }
         if(seenRisk > 0.0 && m_plan.riskMoney > seenRisk * 1.05 + 0.01)
           {
            m_phase = AI_PHASE_PREVIEW;
            Status("The risk grew since the preview. Check it and confirm again", 1, 0);
            return;
           }
         if(m_exec.Send(m_spec, m_plan, cfg, r))
           {
            OnSent(r);
            return;
           }
         if(r.retcode != TRADE_RETCODE_REQUOTE && r.retcode != TRADE_RETCODE_PRICE_CHANGED && r.retcode != TRADE_RETCODE_PRICE_OFF)
            break;
        }
      Fail(r.msg);
     }

   // A risk this close to the plan's counts as the plan's: moving a stop to the tick grid can shift it a little.
   double            RiskTolerance() const
     {
      return MathMax(0.01, m_plan.riskMoney * 0.005);
     }

   // "Filled 3.0 pips worse. SL/TP moved: risk $100.00 as planned". Short, to fit the panel's two
   // status lines; the log has the order and the prices.
   string            FillText(const AiFillReport &f) const
     {
      string text = "Filled " + DoubleToString(MathAbs(f.slipPips), 1) + " pips " + ((f.slipPips > 0.0) ? "worse" : "better") + ". ";
      if(f.notMoved != "")
         text += "SL/TP not moved";
      else if(f.slMoved && f.tpMoved)
         text += "SL/TP moved";
      else if(f.slMoved)
         text += "SL moved, TP kept";
      else if(f.tpMoved)
         text += "SL kept, TP moved";
      else
         text += "SL/TP kept";
      if(f.sl <= 0.0)
         return text;
      string cur = Currency();
      if(MathAbs(f.risk - m_plan.riskMoney) <= RiskTolerance())
         return text + ": risk " + AiMoney(f.risk, cur) + " as planned";
      return text + ": risk " + AiMoney(f.risk, cur) + " (plan " + AiMoney(m_plan.riskMoney, cur) + ")";
     }

   void              OnSent(const AiSendResult &r)
     {
      SaveMemory();
      string msg = AiOrderTypeName(m_plan.type) + " " + AiLotsStr(m_spec, r.volume) + " " + _Symbol +
                   (m_plan.pending ? " placed at " : " filled at ") + AiPriceStr(m_spec, r.price);
      AiLog(msg + " | SL " + AiPriceStr(m_spec, m_plan.sl) + " TP " + AiPriceStr(m_spec, m_plan.tp) +
            " | risk " + DoubleToString(m_plan.riskMoney, 2) + " (" + DoubleToString(m_plan.riskPct, 2) + "%)" +
            " | ticket " + IntegerToString((long)r.ticket));
      int level = 3;
      AiFillReport f;
      AiAfterFill(m_exec, m_spec, m_plan, cfg, m_slMode, m_tpMode, m_tpValue, r, f);
      if(f.slipped)
        {
         msg = FillText(f);
         if(f.sl > 0.0 && f.risk > m_plan.riskMoney + RiskTolerance())
            level = 1;
         AiLog("Slippage: planned " + AiPriceStr(m_spec, m_plan.entry) + ", filled " + AiPriceStr(m_spec, r.price) + " (" +
               DoubleToString(f.slipPips, 1) + " pips) | SL " + AiPriceStr(m_spec, f.sl) + " TP " + AiPriceStr(m_spec, f.tp) +
               ((f.notMoved != "") ? " | not moved: " + f.notMoved : "") + " | risk " + DoubleToString(f.risk, 2) + ", planned " +
               DoubleToString(m_plan.riskMoney, 2));
        }
      Status(msg, level, 8000);
      if(cfg.sounds)
         PlaySound("ok.wav");
      m_phase = AI_PHASE_COOLDOWN;
      m_afterCooldown = AI_PHASE_IDLE;
      m_cooldownUntil = AiNowMs() + 700;
     }

   void              Fail(const string msg)
     {
      string text = "Not sent: " + ((msg != "") ? msg : "unknown error");
      Status(text, 2, 0);
      AiLog(text + " | " + AiOrderTypeName(m_plan.type) + " " + AiLotsStr(m_spec, m_plan.lots) + " @ " + AiPriceStr(m_spec, m_plan.entry) +
            " SL " + AiPriceStr(m_spec, m_plan.sl) + " TP " + AiPriceStr(m_spec, m_plan.tp) +
            " | filling flags " + IntegerToString(m_spec.fillingFlags) + ", execution " + IntegerToString(m_spec.exeMode));
      if(cfg.sounds)
         PlaySound("timeout.wav");
      m_phase = AI_PHASE_COOLDOWN;
      m_afterCooldown = AI_PHASE_PREVIEW;
      m_cooldownUntil = AiNowMs() + 700;
     }

   //--- changes to open trades ------------------------------------------
   string            TicketText(const ulong ticket) const
     {
      return "#" + IntegerToString((long)ticket);
     }

   bool              SamePrice(const double a, const double b) const
     {
      return MathAbs(a - b) < MathMax(m_spec.point, 1e-10) * 0.5;
     }

   int               LiveIndex(const ulong ticket) const
     {
      int n = ArraySize(m_live);
      for(int i = 0; i < n; i++)
         if(m_live[i].ticket == ticket)
            return i;
      return -1;
     }

   int               PriceY(const double price) const
     {
      int px = 0;
      int py = 0;
      if(!ChartTimePriceToXY(0, 0, TimeCurrent(), price, px, py))
         return (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0) / 2;
      return py;
     }

   double            ModLevel(const int which) const
     {
      if(which == 0)
         return m_modOpen;
      if(which == 1)
         return m_modSl;
      return m_modTp;
     }

   void              CloseEdit()
     {
      m_modOn = false;
      m_modDragging = false;
      m_modStatus = "";
      m_refreshEdits = true;
     }

   // Starts the change of the trade whose line or tag the trader used, or keeps the one already
   // open for it. One card, one trade: another trade's open change is dropped.
   bool              EditTrade(const ulong ticket)
     {
      if(m_modOn && m_modLive.ticket == ticket)
         return true;
      int i = LiveIndex(ticket);
      if(i < 0)
         return false;
      if(AiIsStopLimit(m_live[i].type))
        {
         Status("Change a stop-limit order in MT5's Trade tab", 0, 5000);
         return false;
        }
      if(m_modOn)
         Status("The change to " + TicketText(m_modLive.ticket) + " was dropped. Nothing was sent", 0, 5000);
      m_modOn = true;
      m_modLive = m_live[i];
      m_modOpen = m_live[i].open;
      m_modSl = m_live[i].sl;
      m_modTp = m_live[i].tp;
      m_modSince = AiNowMs();
      m_modStatus = "";
      m_refreshEdits = true;
      return true;
     }

   // A pending order's entry takes its stop and target along, so the money at risk stays the same.
   void              SetModLevel(const int which, const double price)
     {
      if(which == 0)
        {
         if(!m_modLive.isOrder || price <= 0.0)
            return;
         AiMoveEntry(m_spec, price, m_modOpen, m_modSl, m_modTp);
        }
      else if(which == 1)
         m_modSl = price;
      else
         m_modTp = price;
      m_modStatus = "";
      m_refreshEdits = true;
     }

   // A line of an open trade is moving under the mouse. Only the change on the card follows it.
   void              OnOrderLine(const ulong ticket, const int which, const double raw)
     {
      double price = AiNormPrice(m_spec, raw);
      if(price <= 0.0 || !EditTrade(ticket))
         return;
      SetModLevel(which, price);
      m_modWhich = which;
      m_modDragging = true;
     }

   // The line was let go: the card opens level with it.
   void              DropOrderLine()
     {
      m_orderDrag = false;
      m_orders.EndDrag();
      if(!m_modOn || !m_modDragging)
         return;
      m_modDragging = false;
      m_modY = PriceY(ModLevel(m_modWhich));
      m_modSince = AiNowMs();
      m_refreshEdits = true;   // the card's fields still hold the last card's text
     }

   // A click on a trade's tag opens the card without moving anything, to type a level instead.
   void              OnOrderTag(const ulong ticket, const int which, const int y)
     {
      if(!EditTrade(ticket))
         return;
      m_modWhich = which;
      m_modDragging = false;
      m_modY = y;
      m_modSince = AiNowMs();
      m_refreshEdits = true;
     }

   void              ModCancel()
     {
      if(!m_modOn)
         return;
      CloseEdit();
      Status("Change discarded. Nothing was sent", 0, 2500);
     }

   // Reads the trades on the symbol and checks the open change with fresh prices. Returns true when
   // the server's values for that trade moved since the card showed them.
   bool              RebuildMod()
     {
      if(cfg.manageOrders)
         AiReadLive(_Symbol, m_live);
      else
         ArrayResize(m_live, 0);
      if(!m_modOn)
         return false;
      int i = LiveIndex(m_modLive.ticket);
      if(i < 0 || m_live[i].isOrder != m_modLive.isOrder)
        {
         Status(TicketText(m_modLive.ticket) + ((i < 0) ? " is closed" : " was filled") + ". Nothing was changed", 1, 6000);
         CloseEdit();
         return false;
        }
      bool moved = false;
      if(!SamePrice(m_live[i].open, m_modLive.open) || !SamePrice(m_live[i].sl, m_modLive.sl) || !SamePrice(m_live[i].tp, m_modLive.tp) ||
         MathAbs(m_live[i].lots - m_modLive.lots) > 1e-9)
        {
         // Levels the trader did not touch follow the server; the ones they moved stay theirs.
         if(SamePrice(m_modOpen, m_modLive.open))
            m_modOpen = m_live[i].open;
         if(SamePrice(m_modSl, m_modLive.sl))
            m_modSl = m_live[i].sl;
         if(SamePrice(m_modTp, m_modLive.tp))
            m_modTp = m_live[i].tp;
         m_modStatus = TicketText(m_modLive.ticket) + " was changed elsewhere. Check the values, then confirm";
         m_modStatusLevel = 1;
         m_modSince = AiNowMs();
         m_refreshEdits = true;
         moved = true;
        }
      m_modLive = m_live[i];
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(_Symbol, tick);
      AiBuildModPlan(m_spec, m_modLive, m_modOpen, m_modSl, m_modTp, cfg, tick, RiskBaseMoney(), m_mod);
      return moved;
     }

   // "entry 1.08200, SL 1.08000, TP 1.08600": the levels a change moves.
   string            ModLevelsText(const AiLive &was, const double open, const double sl, const double tp) const
     {
      string t = "";
      if(was.isOrder && !SamePrice(open, was.open))
         t = "entry " + AiPriceStr(m_spec, open);
      if(!SamePrice(sl, was.sl))
         t += ((t == "") ? "" : ", ") + "SL " + ((sl > 0.0) ? AiPriceStr(m_spec, sl) : "none");
      if(!SamePrice(tp, was.tp))
         t += ((t == "") ? "" : ", ") + "TP " + ((tp > 0.0) ? AiPriceStr(m_spec, tp) : "none");
      return t;
     }

   void              ModConfirm()
     {
      if(!m_modOn || m_modDragging)
         return;
      if(AiNowMs() - m_modSince < 300)
         return;
      // Fresh symbol data (the broker can change its stops and freeze levels), fresh prices and the
      // trade as the server has it now; if the trade moved, the card shows that first.
      AiLoadSpec(_Symbol, (int)cfg.pipMode, m_spec);
      if(RebuildMod() || !m_modOn)
         return;
      if(!m_mod.valid)
         return;   // the card's status line says why
      string perm = m_exec.PermissionProblem();
      if(perm != "")
        {
         m_permProblem = perm;
         return;
        }
      AiLive was = m_modLive;
      double open = m_mod.open;
      double sl = m_mod.sl;
      double tp = m_mod.tp;
      string levels = ModLevelsText(was, open, sl, tp);
      m_modStatus = "";
      m_modSending = true;
      Draw(true);   // show "Saving..." before OrderSend blocks
      AiSendResult r;
      ZeroMemory(r);
      bool ok = m_exec.Modify(m_spec, was, open, sl, tp, r);
      m_modSending = false;
      m_modBusyUntil = AiNowMs() + 700;
      string before = " | before: entry " + AiPriceStr(m_spec, was.open) + " SL " + AiPriceStr(m_spec, was.sl) + " TP " + AiPriceStr(m_spec, was.tp) +
                      ", " + AiLotsStr(m_spec, was.lots) + " lots";
      if(ok)
        {
         string msg = "Changed " + TicketText(was.ticket) + ": " + levels;
         Status(msg, 3, 8000);
         AiLog(msg + before);
         if(cfg.sounds)
            PlaySound("ok.wav");
         CloseEdit();
        }
      else
        {
         m_modStatus = "Not changed: " + ((r.msg != "") ? r.msg : "unknown error");
         m_modStatusLevel = 2;
         AiLog(m_modStatus + " | " + TicketText(was.ticket) + " " + levels + before);
         if(cfg.sounds)
            PlaySound("timeout.wav");
        }
     }

   //--- pinning ----------------------------------------------------------
   // The template is saved without our objects and with the chart's own settings, over two timer
   // ticks so the chart has applied the changes first. The EA itself is saved in the template.
   void              StartPin(const string name)
     {
      string q = "";
      if(name == "default")
         q = "Save this chart, with ActionInna on it, as MT5's default template?\n\n" +
             "Every new chart you open will then load the panel.\n" +
             "Your current default template is replaced. scripts\\link-mt5.ps1 kept a copy of it as\n" +
             "'default-before-ActionInna' in the Templates menu.\n\nPress OK to save.";
      else
         q = "Save this chart, with ActionInna on it, as the template '" + name + "'?\n\n" +
             "Apply it to any chart with right-click > Templates.\n\nPress OK to save.";
      if(MessageBox(q, AI_NAME, MB_OKCANCEL | MB_ICONQUESTION) != IDOK)
         return;
      m_pinName = name;
      m_pinStep = 1;
      m_menuOpen = false;
      CloseEdit();
      m_orderDrag = false;
      ObjectsDeleteAll(0, AI_OBJ_PREFIX);
      m_ui.Forget();
      m_orders.Forget();
      m_guard.Restore(true);
      m_lastShift = -1.0;
      ChartRedraw();
     }

   void              PinTick()
     {
      if(m_pinStep == 1)
        {
         m_pinStep = 2;
         return;
        }
      ResetLastError();
      bool ok = ChartSaveTemplate(0, m_pinName);
      int err = GetLastError();
      m_pinStep = 0;
      m_guard.Apply(cfg.hideOneClick, cfg.hotkeys, cfg.manageOrders);
      MqlTick tick;
      m_lines.Create((SymbolInfoTick(_Symbol, tick) && tick.bid > 0.0) ? tick.bid : 1.0);
      m_lastSig = "";
      if(ok)
        {
         string done = (m_pinName == "default") ? "Pinned: new charts open with ActionInna" : "Template saved: " + m_pinName;
         Status(done, 3, 8000);
         AiLog(done);
        }
      else
         Status("Could not save the template (error " + IntegerToString(err) + ")", 2, 0);
      Refresh(true);
     }

   //--- input from the chart -----------------------------------------
   void              OnEndEdit(const string name)
     {
      m_editing = "";
      m_lastEndEdit = AiNowMs();
      string text = ObjectGetString(0, name, OBJPROP_TEXT);
      string trimmed = text;
      StringTrimLeft(trimmed);
      StringTrimRight(trimmed);
      double v = 0.0;
      bool ok = AiParseNumber(text, v);
      if(name == AI_P + "E_RISK")
        {
         if(ok && v > 0.0)
           {
            m_custom[m_customUnit] = v;
            SetChip(3);
            SaveSettings();
           }
         else if(trimmed != "")
            Status("Enter a number above zero for the custom risk", 2, 4000);
         else
            SetChip(3);
        }
      else if(name == AI_P + "E_SL")
        {
         if(trimmed == "")
            m_slValue = 0.0;
         else if(ok && v >= 0.0)
            m_slValue = v;
         else
            Status("Enter the stop loss in " + ((m_slMode == AI_LEVEL_PRICE) ? "price" : "pips"), 2, 4000);
        }
      else if(name == AI_P + "E_TP")
        {
         if(trimmed == "")
            m_tpValue = 0.0;
         else if(ok && v >= 0.0)
            m_tpValue = v;
         else
            Status("Enter the take profit as " + ((m_tpMode == AI_LEVEL_PRICE) ? "a price" : ((m_tpMode == AI_LEVEL_RR) ? "an R multiple" : "pips")), 2, 4000);
        }
      else if(name == AI_P + "E_ENTRY")
        {
         if(ok && v > 0.0)
           {
            m_entry = AiNormPrice(m_spec, v);
            m_entryUserSet = true;
            m_pending = true;
           }
         else
            Status("Enter the entry price", 2, 4000);
        }
      else if(name == AI_P + "E_MENTRY" || name == AI_P + "E_MSL" || name == AI_P + "E_MTP")
        {
         int which = (name == AI_P + "E_MENTRY") ? 0 : ((name == AI_P + "E_MSL") ? 1 : 2);
         if(m_modOn)
           {
            if(trimmed == "" && which > 0)
               SetModLevel(which, 0.0);   // an empty field removes that level
            else if(ok && v > 0.0)
               SetModLevel(which, AiNormPrice(m_spec, v));
            else
              {
               m_modStatus = "Enter a price";
               m_modStatusLevel = 2;
              }
            // A click on Confirm right after typing waits until the new numbers are on the card.
            m_modSince = AiNowMs();
           }
        }
      m_refreshEdits = true;
      Refresh(true);
     }

   // Tab / Shift+Tab walk the panel's controls in visual order; the focus ring shows where.
   void              MoveFocus(const int dir)
     {
      int n = m_panel.FocusCount();
      if(n <= 0)
         return;
      int i = m_panel.FocusIndex(m_focusCmd);
      if(i < 0)
         i = (dir > 0) ? 0 : n - 1;
      else
         i = (i + dir + n) % n;
      m_focusCmd = (int)m_panel.FocusCmd(i);
      Refresh(true);
     }

   void              OnKey(const int vk, const double repeat, const string flags)
     {
      int f = (int)StringToInteger(flags);
      if((f & 0x4000) != 0 || repeat > 1.0)
         return;   // auto-repeat of a held key
      if(m_editing != "")
         return;   // typing in a field
      bool shift = AiKeyHeld(TERMINAL_KEYSTATE_SHIFT);
      bool ctrl = AiKeyHeld(TERMINAL_KEYSTATE_CONTROL);

      // Keyboard focus works even with the hotkeys switched off.
      if(vk == 9 && !ctrl)
        {
         MoveFocus(shift ? -1 : 1);
         return;
        }
      if(m_focusCmd != AI_CMD_NONE && !ctrl)
        {
         if((vk == 13 || vk == 32) && !shift)
           {
            // The Enter that finished typing in a field must not also press the focused control.
            if(AiNowMs() - m_lastEndEdit < 500)
               return;
            Exec((ENUM_AI_CMD)m_focusCmd);
            return;
           }
         if(vk == 27)
           {
            m_focusCmd = AI_CMD_NONE;   // first Esc leaves the panel, the next one closes the preview
            Refresh(true);
            return;
           }
        }

      if(!cfg.hotkeys)
         return;
      for(int i = 0; i < AI_KEY_COUNT; i++)
        {
         if(!AiKeyMatch(m_keys[i], vk, shift, ctrl))
            continue;
         ENUM_AI_CMD cmd = KeyCmd(i);
         // While the modify card is open, confirm and cancel belong to it.
         if(m_modOn && !m_modDragging)
           {
            if(cmd == AI_CMD_CONFIRM)
               cmd = AI_CMD_MOD_CONFIRM;
            else if(cmd == AI_CMD_CANCEL)
               cmd = AI_CMD_MOD_CANCEL;
           }
         // The Enter that finished typing in a field must not also confirm the order.
         if((cmd == AI_CMD_CONFIRM || cmd == AI_CMD_MOD_CONFIRM) && AiNowMs() - m_lastEndEdit < 500)
            return;
         Exec(cmd);
         return;
        }
     }

   void              ApplyLinePrice(const int idx, const double raw)
     {
      double price = AiNormPrice(m_spec, raw);
      if(price <= 0.0)
         return;
      if(idx == 0)
        {
         m_pending = true;
         m_entry = price;
         m_entryUserSet = true;
        }
      else if(idx == 1)
        {
         m_slMode = AI_LEVEL_PRICE;
         m_slValue = price;
        }
      else if(idx == 2)
        {
         m_tpMode = AI_LEVEL_PRICE;
         m_tpValue = price;
        }
      m_refreshEdits = true;
     }

   void              OnMouse(const int mx, const int my, const int buttons)
     {
      bool down = ((buttons & 1) != 0);
      m_guard.LockScroll(m_dragPanel || m_panel.Contains(mx, my) || m_panel.InCard(mx, my));
      if(down && !m_mouseDown)
        {
         m_mouseDown = true;
         if(m_panel.InHeader(mx, my, m_ui))
           {
            m_dragPanel = true;
            m_dragDX = mx - m_panel.x;
            m_dragDY = my - m_panel.y;
            m_guard.LockScroll(true);
           }
        }
      else if(!down && m_mouseDown)
        {
         m_mouseDown = false;
         if(m_dragPanel)
           {
            m_dragPanel = false;
            m_panel.docked = (m_panel.x + m_panel.w >= m_panel.chartW - m_ui.S(24));
            SaveSettings();
            Refresh(true);
           }
         // Every release ends a drag, taken or not: the lines are written again from what they
         // should show, so one dropped while an order was being sent goes back to its place.
         if(m_orderDrag)
            DropOrderLine();
         m_lineDrag = false;
         m_lines.EndDrag();
         m_orders.EndDrag();
         Refresh(true);
         return;
        }
      if(!down)
         return;
      ulong now = AiNowMs();
      if(now - m_lastMove < 25)
         return;
      m_lastMove = now;
      if(m_dragPanel)
        {
         m_panel.docked = false;
         m_panel.MoveTo(mx - m_dragDX, my - m_dragDY, m_ui);
         Draw(true);
         return;
        }
      if(cfg.manageOrders && !Busy())
        {
         ulong ticket = 0;
         int which = -1;
         double moved = 0.0;
         if(m_orders.DetectDrag(ticket, which, moved))
           {
            m_orderDrag = true;
            OnOrderLine(ticket, which, moved);
            Refresh(true);
            return;
           }
        }
      if(m_phase != AI_PHASE_PREVIEW)
         return;
      int idx = -1;
      double price = 0.0;
      if(m_lines.DetectDrag(idx, price))
        {
         m_lineDrag = true;
         ApplyLinePrice(idx, price);
         Refresh(true);
        }
     }

   //--- building and drawing ----------------------------------------
   void              Rebuild()
     {
      // Right after MT5 starts or reconnects the symbol may not be synced yet: keep asking.
      if(!m_spec.ok)
         AiLoadSpec(_Symbol, (int)cfg.pipMode, m_spec);
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(_Symbol, tick);
      AiInput in;
      in.side = m_side;
      in.pending = m_pending;
      in.entry = m_entry;
      in.slMode = m_slMode;
      in.slValue = m_slValue;
      in.tpMode = m_tpMode;
      in.tpValue = m_tpValue;
      in.riskMode = m_riskMode;
      in.riskValue = m_riskValue;
      in.riskBase = m_riskBase;
      AiBuildPlan(m_spec, in, cfg, tick, m_plan);
     }

   void              ComposeView(AiView &v)
     {
      string cur = Currency();
      string curSym = (cur == "USD") ? "$" : cur;
      bool hasLots = (m_plan.lots > 0.0);
      v.symbol = _Symbol;
      v.bid = (m_plan.bid > 0.0) ? AiPriceStr(m_spec, m_plan.bid) : "-";
      v.ask = (m_plan.ask > 0.0) ? AiPriceStr(m_spec, m_plan.ask) : "-";
      v.spread = (m_plan.ask > 0.0) ? "Spread " + DoubleToString(m_plan.spreadPips, 1) + " pips" : "";
      v.phase = m_phase;
      v.side = m_side;
      v.pending = m_pending;
      v.compact = m_compact;
      v.forcedCompact = m_forcedCompact;
      v.menuOpen = m_menuOpen;
      v.riskShort = (m_riskMode == AI_RISK_LOTS) ? RiskShort() : "Risk " + RiskShort();
      for(int i = 0; i < 3; i++)
         v.chipText[i] = AiTrimZeros(DoubleToString(cfg.preset[i], 2)) + "%";
      v.chip = m_chip;
      if(m_customUnit == AI_RISK_PERCENT)
         v.customUnit = "%";
      else if(m_customUnit == AI_RISK_MONEY)
         v.customUnit = curSym;
      else
         v.customUnit = "lot";
      double cv = m_custom[m_customUnit];
      v.customText = (cv > 0.0) ? AiTrimZeros(DoubleToString(cv, (m_customUnit == AI_RISK_LOTS) ? m_spec.volDigits : 2)) : "";
      string baseName = (m_riskBase == AI_BASE_BALANCE) ? "balance" : "equity";
      if(m_riskMode == AI_RISK_LOTS)
         v.riskLabel = "Position size: fixed lots";
      else if(m_riskMode == AI_RISK_MONEY)
         v.riskLabel = "Risk per trade: amount in " + cur;
      else
         v.riskLabel = "Risk per trade: % of " + baseName;

      v.slUnit = (m_slMode == AI_LEVEL_PRICE) ? "price" : "pips";
      if(m_slValue <= 0.0)
         v.slText = "";
      else if(m_slMode == AI_LEVEL_PRICE)
         v.slText = AiPriceStr(m_spec, m_slValue);
      else
         v.slText = AiTrimZeros(DoubleToString(m_slValue, 1));
      if(m_tpMode == AI_LEVEL_PRICE)
         v.tpUnit = "price";
      else if(m_tpMode == AI_LEVEL_RR)
         v.tpUnit = "R";
      else
         v.tpUnit = "pips";
      if(m_tpValue <= 0.0)
         v.tpText = "";
      else if(m_tpMode == AI_LEVEL_PRICE)
         v.tpText = AiPriceStr(m_spec, m_tpValue);
      else if(m_tpMode == AI_LEVEL_RR)
         v.tpText = AiTrimZeros(DoubleToString(m_tpValue, 2));
      else
         v.tpText = AiTrimZeros(DoubleToString(m_tpValue, 1));
      v.entryText = (m_entry > 0.0) ? AiPriceStr(m_spec, m_entry) : "";
      v.entryType = (m_pending && m_plan.entry > 0.0) ? AiOrderTypeName(m_plan.type) : "";

      string unitWord = (MathAbs(m_plan.units - 1.0) < 1e-9) ? " unit)" : " units)";
      v.lots = hasLots ? AiLotsStr(m_spec, m_plan.lots) + "  (" + AiGroup(m_plan.units, 0) + unitWord : "-";
      v.risk = (m_plan.riskMoney > 0.0) ? AiMoney(-m_plan.riskMoney, cur) + "  (" + DoubleToString(m_plan.riskPct, 2) + "%)" : "-";
      v.reward = (hasLots && m_plan.tp > 0.0) ? AiMoney(m_plan.rewardMoney, cur, true) + "  (" + DoubleToString(m_plan.rewardPct, 2) + "%)" : "-";
      v.rr = (m_plan.rr > 0.0) ? "1:" + DoubleToString(m_plan.rr, 2) : "-";
      v.pips = (m_plan.slPips > 0.0 || m_plan.tpPips > 0.0) ? "SL " + DoubleToString(m_plan.slPips, 1) + "   TP " + DoubleToString(m_plan.tpPips, 1) : "-";
      v.pipValue = hasLots ? AiMoney(m_plan.pipValue, cur) : "-";
      v.margin = hasLots ? AiMoney(m_plan.margin, cur) + "  (free " + AiMoney(m_plan.freeAfter, cur, false, 0) + ")" : "-";
      v.showCommission = (cfg.commissionRT > 0.0);
      v.commission = hasLots ? AiMoney(m_plan.commission, cur) : "-";

      if(m_phase == AI_PHASE_SENDING)
        {
         v.confirmText = "Sending...";
         v.confirmEnabled = false;
        }
      else if(m_phase == AI_PHASE_PREVIEW || m_phase == AI_PHASE_COOLDOWN)
        {
         string what = (m_pending && m_plan.entry > 0.0) ? AiOrderTypeName(m_plan.type) : ((m_side == AI_BUY) ? "BUY" : "SELL");
         v.confirmText = (m_pending ? "Place " : "Confirm ") + what + (hasLots ? " " + AiLotsStr(m_spec, m_plan.lots) + " lots" : "");
         v.confirmEnabled = (m_phase == AI_PHASE_PREVIEW && m_plan.valid);
        }
      else
        {
         v.confirmText = m_oneClick ? "One-click: SELL/BUY send at once" : "Press SELL or BUY to preview";
         v.confirmEnabled = false;
        }
      // X closes the preview or the menu; with neither open it would do nothing, so it is hidden.
      v.showCancel = (m_phase == AI_PHASE_PREVIEW || m_menuOpen);

      ulong now = AiNowMs();
      bool transient = (m_status != "" && (m_statusUntil == 0 || now < m_statusUntil));
      v.statusLevel = 0;
      if(m_permProblem != "")
        {
         v.status = m_permProblem;
         v.statusLevel = 2;
        }
      else if(m_plan.noData)
        {
         // Loading state, in every phase: BUY/SELL show "-" until the data arrives.
         v.status = m_plan.err;
         v.statusLevel = 0;
        }
      else if(transient)
        {
         v.status = m_status;
         v.statusLevel = m_statusLevel;
        }
      else if(m_phase == AI_PHASE_PREVIEW && m_plan.err != "")
        {
         v.status = m_plan.err;
         v.statusLevel = 2;
        }
      else if(m_phase == AI_PHASE_PREVIEW && m_plan.warn != "")
        {
         v.status = m_plan.warn;
         v.statusLevel = 1;
        }
      else if(m_phase == AI_PHASE_PREVIEW && m_netting)
        {
         v.status = "Netting account: this order merges with any open position on the symbol and replaces its SL/TP";
         v.statusLevel = 1;
        }
      else if(m_phase == AI_PHASE_PREVIEW)
         v.status = "Drag the lines or edit the values, then confirm. Nothing is sent before that";
      else
         v.status = KeyHint();

      v.autoRecall = m_autoRecall;
      v.oneClick = m_oneClick;
      v.baseName = (m_riskBase == AI_BASE_BALANCE) ? "Balance" : "Equity";
      v.editing = m_editing;
      v.refreshEdits = m_refreshEdits;
      v.focusCmd = m_focusCmd;

      // The modify card waits for the mouse to let go of the line.
      v.modOpen = (m_modOn && !m_modDragging);
      if(!v.modOpen)
         return;
      v.modSide = m_modLive.side;
      v.modY = m_modY;
      string what = m_modLive.isOrder ? AiOrderTypeName(m_modLive.type) : ((m_modLive.side == AI_BUY) ? "BUY" : "SELL");
      v.modTitle = "Modify " + what + " " + AiLotsStr(m_spec, m_modLive.lots) + " " + _Symbol;
      v.modTicket = TicketText(m_modLive.ticket);
      v.modEntryEdit = m_modLive.isOrder;
      v.modEntryText = AiPriceStr(m_spec, m_mod.open);
      v.modEntryWas = (m_modLive.isOrder && !SamePrice(m_mod.open, m_modLive.open)) ? "was " + AiPriceStr(m_spec, m_modLive.open) : "";
      v.modEntryMoney = m_modLive.isOrder ? "" : "Now " + AiMoney(m_modLive.profit, cur, true);
      v.modEntryTone = m_modLive.isOrder ? 0 : ((m_modLive.profit < 0.0) ? -1 : 1);
      v.modSlText = (m_mod.sl > 0.0) ? AiPriceStr(m_spec, m_mod.sl) : "";
      v.modSlWas = SamePrice(m_mod.sl, m_modLive.sl) ? "" : "was " + ((m_modLive.sl > 0.0) ? AiPriceStr(m_spec, m_modLive.sl) : "none");
      v.modSlMoney = (m_mod.sl > 0.0) ? AiMoney(m_mod.slMoney, cur, true) + "  (" + AiSignedPct(m_mod.slPct) + ")" : "-";
      v.modSlTone = (m_mod.sl <= 0.0) ? 0 : ((m_mod.slMoney < 0.0) ? -1 : 1);
      v.modTpText = (m_mod.tp > 0.0) ? AiPriceStr(m_spec, m_mod.tp) : "";
      v.modTpWas = SamePrice(m_mod.tp, m_modLive.tp) ? "" : "was " + ((m_modLive.tp > 0.0) ? AiPriceStr(m_spec, m_modLive.tp) : "none");
      v.modTpMoney = (m_mod.tp > 0.0) ? AiMoney(m_mod.tpMoney, cur, true) + "  (" + AiSignedPct(m_mod.tpPct) + ")" : "-";
      v.modTpTone = (m_mod.tp <= 0.0) ? 0 : ((m_mod.tpMoney < 0.0) ? -1 : 1);
      if(m_mod.rr > 0.0)
         v.modRR = "1:" + DoubleToString(m_mod.rr, 2);
      else if(m_mod.sl > 0.0 && (m_mod.sl - m_mod.open) * m_modLive.side >= 0.0)
         v.modRR = "Stop at break-even or better";
      else
         v.modRR = "-";
      v.modStatusLevel = 0;
      if(m_modSending)
         v.modStatus = "Saving the change...";
      else if(m_permProblem != "")
        {
         v.modStatus = m_permProblem;
         v.modStatusLevel = 2;
        }
      else if(m_modStatus != "")
        {
         v.modStatus = m_modStatus;
         v.modStatusLevel = m_modStatusLevel;
        }
      else if(m_mod.err != "")
        {
         v.modStatus = m_mod.err;
         v.modStatusLevel = 2;
        }
      else if(m_mod.warn != "")
        {
         v.modStatus = m_mod.warn;
         v.modStatusLevel = 1;
        }
      else if(!m_mod.changed)
         v.modStatus = "Drag a line or type a price. Nothing is sent before Confirm";
      else
         v.modStatus = "Nothing changes on the server until you confirm";
      v.modConfirmText = m_modSending ? "Saving..." : "Confirm change";
      v.modConfirmEnabled = (m_mod.valid && !m_modSending && !Busy() && m_permProblem == "");
     }

   string            ViewSignature(const int cw, const int ch) const
     {
      return m_view.bid + "|" + m_view.ask + "|" + m_view.spread + "|" + m_view.lots + "|" + m_view.risk + "|" + m_view.reward + "|" +
             m_view.rr + "|" + m_view.pips + "|" + m_view.pipValue + "|" + m_view.margin + "|" + m_view.commission + "|" +
             m_view.status + "|" + IntegerToString(m_view.statusLevel) + "|" + m_view.confirmText + (m_view.confirmEnabled ? "1" : "0") + "|" +
             m_view.slText + m_view.slUnit + "|" + m_view.tpText + m_view.tpUnit + "|" + m_view.entryText + m_view.entryType + "|" +
             m_view.customText + m_view.customUnit + m_view.riskLabel + "|" + IntegerToString(m_view.chip) + IntegerToString(m_view.phase) +
             IntegerToString(m_view.side) + (m_view.pending ? "P" : "M") + (m_view.compact ? "C" : "E") + (m_view.forcedCompact ? "F" : "-") +
             (m_view.menuOpen ? "O" : "-") + (m_view.showCancel ? "X" : "-") + (m_view.autoRecall ? "A" : "-") + (m_view.oneClick ? "1" : "-") +
             m_view.baseName + m_view.riskShort + "|" + m_view.editing + (m_view.refreshEdits ? "R" : "") + "|" + IntegerToString(m_view.focusCmd) + "|" +
             IntegerToString(m_panel.x) + "," + IntegerToString(m_panel.y) + "," + IntegerToString(cw) + "," + IntegerToString(ch) + "|" + CardSignature();
     }

   string            CardSignature() const
     {
      if(!m_view.modOpen)
         return "-";
      return IntegerToString(m_view.modY) + m_view.modTitle + m_view.modTicket + "|" + m_view.modEntryText + m_view.modEntryWas + m_view.modEntryMoney + "|" +
             m_view.modSlText + m_view.modSlWas + m_view.modSlMoney + "|" + m_view.modTpText + m_view.modTpWas + m_view.modTpMoney + "|" +
             m_view.modRR + "|" + m_view.modStatus + IntegerToString(m_view.modStatusLevel) + "|" + m_view.modConfirmText + (m_view.modConfirmEnabled ? "1" : "0");
     }

   void              UpdateShift(const int cw)
     {
      double want = -1.0;   // -1 = the trader's own chart shift
      if(cfg.autoShift && m_panel.docked && !m_compact && cw > 0)
         want = MathMax(10.0, MathMin(50.0, (m_panel.w + m_ui.S(24)) * 100.0 / cw));
      if(MathAbs(want - m_lastShift) < 0.5)
         return;
      m_lastShift = want;
      if(want < 0.0)
         m_guard.Shift(false, 0.0);
      else
         m_guard.Shift(true, want);
     }

   void              Draw(const bool force)
     {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
      m_panel.Place(cw, ch, m_ui);
      // A chart shorter than the full panel gets the slim layout, so CONFIRM never falls off it.
      m_forcedCompact = !m_panel.FullFits(m_ui);
      m_compact = (m_collapsed || m_forcedCompact);
      bool tagsLeft = (m_panel.x + m_panel.w / 2 > cw / 2);
      bool redraw = force;
      // Open trades first. Objects they create are drawn over the panel, so the panel and the card
      // are then drawn again on top, but never under a field the trader is typing in.
      if(cfg.manageOrders)
        {
         ulong editTicket = 0;
         if(m_modOn)
            editTicket = m_modLive.ticket;
         if(m_orders.Sync(m_live, editTicket, m_mod, m_spec, m_theme, RiskBaseMoney(), cfg.commissionRT, tagsLeft, cw, ch, m_ui, Currency()))
            m_raisePanel = true;
        }
      if(m_raisePanel && m_editing == "")
        {
         m_raisePanel = false;
         ObjectsDeleteAll(0, AI_P);
         m_ui.Forget();
         redraw = true;
        }
      ComposeView(m_view);
      string sig = ViewSignature(cw, ch);
      if(redraw || sig != m_lastSig)
        {
         m_lastSig = sig;
         m_ui.BeginFrame();
         m_panel.Render(m_view, m_theme, m_ui);
         m_panel.RenderCard(m_view, m_theme, m_ui);
         m_ui.EndFrame();
         m_refreshEdits = false;
        }
      bool show = (m_phase == AI_PHASE_PREVIEW || m_phase == AI_PHASE_SENDING ||
                   (m_phase == AI_PHASE_COOLDOWN && m_afterCooldown == AI_PHASE_PREVIEW));
      m_lines.Sync(m_plan, m_spec, m_theme, show, cfg.showZones, tagsLeft, cw, ch, m_ui, Currency());
      UpdateShift(cw);
      ChartRedraw();
     }

   void              Refresh(const bool force)
     {
      if(m_tester || !m_inited || m_pinStep != 0)
         return;
      ulong now = AiNowMs();
      if(!force && now - m_lastRefresh < 100)
         return;
      m_lastRefresh = now;
      Rebuild();
      RebuildMod();
      Draw(force);
     }

   void              Exec(const ENUM_AI_CMD cmd)
     {
      if(cmd == AI_CMD_NONE)
         return;
      if(Busy() || m_pinStep != 0)
         return;
      if(m_statusUntil == 0)
         m_status = "";   // a message without a timeout lasts until the next action
      switch(cmd)
        {
         case AI_CMD_BUY:
            OnSide(AI_BUY);
            break;
         case AI_CMD_SELL:
            OnSide(AI_SELL);
            break;
         case AI_CMD_CONFIRM:
            Confirm();
            break;
         case AI_CMD_CANCEL:
            Cancel();
            break;
         case AI_CMD_RISK1:
            SetChip(0);
            SaveSettings();
            break;
         case AI_CMD_RISK2:
            SetChip(1);
            SaveSettings();
            break;
         case AI_CMD_RISK3:
            SetChip(2);
            SaveSettings();
            break;
         case AI_CMD_RISKC:
            SetChip(3);
            SaveSettings();
            break;
         case AI_CMD_RISK_UNIT:
            CycleUnit();
            break;
         case AI_CMD_SL_MODE:
            CycleSLMode();
            break;
         case AI_CMD_TP_MODE:
            CycleTPMode();
            break;
         case AI_CMD_SL_RECALL:
            RecallLevel(true, false);
            break;
         case AI_CMD_TP_RECALL:
            RecallLevel(false, true);
            break;
         case AI_CMD_RECALL:
            RecallLevel(true, true);
            break;
         case AI_CMD_KIND:
            TogglePending();
            break;
         case AI_CMD_MENU:
            m_menuOpen = !m_menuOpen;
            break;
         case AI_CMD_COLLAPSE:
            m_collapsed = !m_collapsed;
            SaveSettings();
            if(m_forcedCompact && !m_collapsed)
               Status("This chart is too short for the full panel. Make the chart taller to expand it", 0, 5000);
            break;
         case AI_CMD_RISK_NEXT:
            SetChip((m_chip + 1) % 4);
            SaveSettings();
            Status("Risk: " + RiskShort(), 0, 3000);
            break;
         case AI_CMD_OPT_AUTO:
            m_autoRecall = !m_autoRecall;
            SaveSettings();
            Status(m_autoRecall ? "SL/TP will be set from your last trade on the symbol" : "SL/TP start from the defaults", 0, 4000);
            break;
         case AI_CMD_OPT_ONECLICK:
            ToggleOneClick();
            break;
         case AI_CMD_OPT_BASE:
            m_riskBase = (m_riskBase == AI_BASE_EQUITY) ? AI_BASE_BALANCE : AI_BASE_EQUITY;
            SaveSettings();
            break;
         case AI_CMD_PIN:
            StartPin("default");
            break;
         case AI_CMD_TEMPLATE:
            StartPin(AI_TEMPLATE_NAME);
            break;
         case AI_CMD_MOD_CONFIRM:
            ModConfirm();
            break;
         case AI_CMD_MOD_CANCEL:
            ModCancel();
            break;
         default:
            break;
        }
      Refresh(true);
     }

public:
                     CAiApp()
     {
      ZeroMemory(m_hist);
      m_histTried = false;
      m_histFound = false;
      m_recallSL = 0;
      m_recallTP = 0;
      m_phase = AI_PHASE_IDLE;
      m_afterCooldown = AI_PHASE_IDLE;
      m_side = AI_BUY;
      m_pending = false;
      m_entry = 0.0;
      m_entryUserSet = false;
      m_defaultsSig = "";
      m_slMode = AI_LEVEL_PIPS;
      m_slValue = 0.0;
      m_tpMode = AI_LEVEL_RR;
      m_tpValue = 2.0;
      m_riskMode = AI_RISK_PERCENT;
      m_riskValue = 1.0;
      m_chip = 0;
      m_customUnit = AI_RISK_PERCENT;
      m_custom[0] = 0.5;
      m_custom[1] = 50.0;
      m_custom[2] = 0.0;
      m_riskBase = AI_BASE_EQUITY;
      m_autoRecall = true;
      m_oneClick = false;
      m_collapsed = false;
      m_compact = false;
      m_forcedCompact = false;
      m_menuOpen = false;
      m_refreshEdits = true;
      m_focusCmd = AI_CMD_NONE;
      m_status = "";
      m_statusLevel = 0;
      m_statusUntil = 0;
      m_permProblem = "";
      m_netting = false;
      m_symbol = "";
      m_inited = false;
      m_tester = false;
      m_lastDeinit = 0;
      m_cooldownUntil = 0;
      m_previewSince = 0;
      m_lastEndEdit = 0;
      m_editingSince = 0;
      m_editing = "";
      m_lastRefresh = 0;
      m_lastPermCheck = 0;
      m_lastSig = "";
      m_lastShift = -1.0;
      m_mouseDown = false;
      m_dragPanel = false;
      m_dragDX = 0;
      m_dragDY = 0;
      m_lineDrag = false;
      m_orderDrag = false;
      m_lastMove = 0;
      m_pinStep = 0;
      m_pinName = "";
      m_modOn = false;
      m_modDragging = false;
      ZeroMemory(m_modLive);
      m_modOpen = 0.0;
      m_modSl = 0.0;
      m_modTp = 0.0;
      m_modWhich = 1;
      ZeroMemory(m_mod);
      m_modSince = 0;
      m_modY = 0;
      m_modStatus = "";
      m_modStatusLevel = 0;
      m_modSending = false;
      m_modBusyUntil = 0;
      m_raisePanel = false;
     }

   int               Init()
     {
      m_tester = (MQLInfoInteger(MQL_TESTER) != 0);
      if(m_tester)
        {
         Print(AI_NAME, " is a manual trading panel. The Strategy Tester sends no clicks, so it stays idle here.");
         return INIT_SUCCEEDED;
        }
      g_aiDebugLog = cfg.debugLog;
      FolderCreate(AI_FILES_DIR, FILE_COMMON);
      FolderCreate(AI_FILES_DIR + "\\recall", FILE_COMMON);
      FolderCreate(AI_FILES_DIR, 0);

      // A timeframe/symbol change or new inputs keep the EA loaded: keep the trader's state.
      bool keep = (m_inited && (m_lastDeinit == REASON_CHARTCHANGE || m_lastDeinit == REASON_PARAMETERS));
      bool symbolChanged = (m_symbol != _Symbol);
      m_symbol = _Symbol;
      AiLoadSpec(_Symbol, (int)cfg.pipMode, m_spec);
      if(!keep)
        {
         LoadSettings();
         DefaultLevels();
         m_phase = AI_PHASE_IDLE;
         m_side = AI_BUY;
         m_pending = false;
         m_oneClick = cfg.oneClick;
         m_menuOpen = false;
        }
      else
        {
         if(symbolChanged)
           {
            DefaultLevels();
            m_phase = AI_PHASE_IDLE;
            m_pending = false;
           }
         if(m_lastDeinit == REASON_PARAMETERS)
           {
            // m_store still holds what Deinit saved with the previous inputs.
            m_oneClick = cfg.oneClick;
            if(m_store.GetB("auto_input", cfg.autoRecall) != cfg.autoRecall)
               m_autoRecall = cfg.autoRecall;
            if((int)m_store.GetI("base_input", (long)cfg.riskBase) != (int)cfg.riskBase)
               m_riskBase = (int)cfg.riskBase;
            if(DefaultsSig() != m_defaultsSig)
              {
               DefaultLevels();
               m_phase = AI_PHASE_IDLE;
               m_pending = false;
              }
           }
         if(m_phase == AI_PHASE_SENDING || m_phase == AI_PHASE_COOLDOWN)
            m_phase = AI_PHASE_IDLE;
        }
      m_defaultsSig = DefaultsSig();
      SetChip(m_chip);
      m_histTried = false;
      ReloadMemory();
      m_netting = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

      double dpi = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
      if(dpi <= 0.0)
         dpi = 96.0;
      double sc = dpi / 96.0 * ((cfg.uiScale > 0.0) ? cfg.uiScale : 1.0);
      m_ui.scale = MathMax(0.75, MathMin(3.0, sc));
      m_ui.fontScale = MathMax(0.5, MathMin(3.0, (cfg.uiScale > 0.0) ? cfg.uiScale : 1.0));
      m_ui.font = (cfg.font != "") ? cfg.font : "Arial";
      m_ui.fontSize = (int)MathMax(7, MathMin(16, cfg.fontSize));
      if(m_panel.prefY <= 0)
         m_panel.prefY = m_ui.S(24);
      AiBuildTheme((int)cfg.theme, (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND), m_theme);
      ParseKeys();

      m_guard.Capture();
      m_guard.Apply(cfg.hideOneClick, cfg.hotkeys, cfg.manageOrders);
      m_lastShift = -1.0;

      // Lines and tags first, so the panel created after them is drawn on top.
      ObjectsDeleteAll(0, AI_OBJ_PREFIX);
      m_ui.Forget();
      m_orders.Forget();
      MqlTick tick;
      m_lines.Create((SymbolInfoTick(_Symbol, tick) && tick.bid > 0.0) ? tick.bid : 1.0);
      m_lastSig = "";
      m_mouseDown = false;
      m_dragPanel = false;
      m_lineDrag = false;
      m_orderDrag = false;
      // A change that was open is dropped; nothing of it was sent.
      m_modOn = false;
      m_modDragging = false;
      m_modSending = false;
      m_modStatus = "";
      m_raisePanel = false;
      m_editing = "";
      m_pinStep = 0;
      m_lastPermCheck = AiNowMs();
      m_permProblem = m_exec.PermissionProblem();
      m_refreshEdits = true;

      EventSetMillisecondTimer(200);
      m_inited = true;
      if(keep && m_lastDeinit == REASON_PARAMETERS)
         SaveSettings();   // records the new inputs as the ones in force
      if(!keep || symbolChanged)
         AiLog("Started. Pip " + DoubleToString(m_spec.pipSize, m_spec.digits) + ", stops level " + IntegerToString(m_spec.stopsLevel) +
               " pts, filling flags " + IntegerToString(m_spec.fillingFlags) + ", execution " + IntegerToString(m_spec.exeMode) +
               ", volume " + AiLotsStr(m_spec, m_spec.volMin) + "-" + AiLotsStr(m_spec, m_spec.volMax) + " step " + AiLotsStr(m_spec, m_spec.volStep));
      Refresh(true);
      return INIT_SUCCEEDED;
     }

   void              Deinit(const int reason)
     {
      if(m_tester)
         return;
      EventKillTimer();
      SaveSettings();
      m_lastDeinit = reason;
      ObjectsDeleteAll(0, AI_OBJ_PREFIX);
      m_ui.Forget();
      if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS)
         m_guard.LockScroll(false);
      else
         m_guard.Restore(false);
      ChartRedraw();
     }

   void              Tick()
     {
      if(m_tester || !m_inited)
         return;
      Refresh(false);
     }

   void              Timer()
     {
      if(m_tester || !m_inited)
         return;
      if(m_pinStep != 0)
        {
         PinTick();
         return;
        }
      ulong now = AiNowMs();
      if(m_phase == AI_PHASE_COOLDOWN && now >= m_cooldownUntil)
        {
         m_phase = m_afterCooldown;
         if(m_phase == AI_PHASE_PREVIEW)
            m_previewSince = now;
         m_lastSig = "";
        }
      if(m_editing != "" && now - m_editingSince > 60000)
         m_editing = "";
      if(now - m_lastPermCheck >= 1000)
        {
         m_lastPermCheck = now;
         m_permProblem = m_exec.PermissionProblem();
         // Stops level, trade mode and volume limits can change during the session.
         AiLoadSpec(_Symbol, (int)cfg.pipMode, m_spec);
        }
      Refresh(false);
     }

   void              ChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
     {
      if(m_tester || !m_inited || m_pinStep != 0)
         return;
      if(id == CHARTEVENT_OBJECT_CLICK)
        {
         // A click on an open trade's tag opens the modify card for it.
         if(StringFind(sparam, AI_O) == 0)
           {
            ulong ticket = 0;
            int which = -1;
            string part = "";
            if(cfg.manageOrders && !Busy() && m_orders.Parse(sparam, ticket, which, part) && (part == "b" || part == "x"))
              {
               OnOrderTag(ticket, which, (int)dparam);
               Refresh(true);
              }
            return;
           }
         // A mouse click takes over from keyboard focus.
         if(StringFind(sparam, AI_P) == 0)
            m_focusCmd = AI_CMD_NONE;
         if(StringFind(sparam, AI_P + "E_") == 0)
           {
            m_editing = sparam;
            m_editingSince = AiNowMs();
            return;
           }
         if(StringFind(sparam, AI_P) == 0)
            Exec(m_panel.CmdFromName(sparam));
         return;
        }
      if(id == CHARTEVENT_OBJECT_ENDEDIT)
        {
         if(StringFind(sparam, AI_P + "E_") == 0)
            OnEndEdit(sparam);
         return;
        }
      if(id == CHARTEVENT_OBJECT_DRAG)
        {
         // An open trade's line was dropped: the card opens, nothing is sent.
         if(StringFind(sparam, AI_O) == 0)
           {
            ulong ticket = 0;
            int which = -1;
            string part = "";
            if(cfg.manageOrders && !Busy() && m_orders.Parse(sparam, ticket, which, part) && part == "")
               OnOrderLine(ticket, which, ObjectGetDouble(0, sparam, OBJPROP_PRICE));
            DropOrderLine();
            Refresh(true);
            return;
           }
         int idx = m_lines.IndexOf(sparam);
         if(idx >= 0 && m_phase == AI_PHASE_PREVIEW)
           {
            ApplyLinePrice(idx, ObjectGetDouble(0, sparam, OBJPROP_PRICE));
            m_lines.EndDrag();
            m_lineDrag = false;
            Refresh(true);
           }
         return;
        }
      if(id == CHARTEVENT_KEYDOWN)
        {
         OnKey((int)lparam, dparam, sparam);
         return;
        }
      if(id == CHARTEVENT_MOUSE_MOVE)
        {
         OnMouse((int)lparam, (int)dparam, (int)StringToInteger(sparam));
         return;
        }
      if(id == CHARTEVENT_CHART_CHANGE)
         Refresh(true);
     }
  };

#endif
