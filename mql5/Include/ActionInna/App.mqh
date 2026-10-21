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
#include "Hotkeys.mqh"
#include "Executor.mqh"
#include "ChartGuard.mqh"
#include "Panel.mqh"

// Phases: IDLE (panel only) -> PREVIEW (lines on the chart, CONFIRM armed) -> SENDING -> COOLDOWN
// (ignores clicks and keys queued while OrderSend blocked) -> IDLE after a fill, PREVIEW after a
// failure. The object is a global of the EA, so it survives timeframe and symbol changes.
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
   ulong             m_lastMove;

   int               m_pinStep;
   string            m_pinName;

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

   void              OnSent(const AiSendResult &r)
     {
      SaveMemory();
      string msg = AiOrderTypeName(m_plan.type) + " " + AiLotsStr(m_spec, r.volume) + " " + _Symbol +
                   (m_plan.pending ? " placed at " : " filled at ") + AiPriceStr(m_spec, r.price);
      Status(msg, 3, 8000);
      AiLog(msg + " | SL " + AiPriceStr(m_spec, m_plan.sl) + " TP " + AiPriceStr(m_spec, m_plan.tp) +
            " | risk " + DoubleToString(m_plan.riskMoney, 2) + " (" + DoubleToString(m_plan.riskPct, 2) + "%)" +
            " | ticket " + IntegerToString((long)r.ticket));
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
      ObjectsDeleteAll(0, AI_OBJ_PREFIX);
      m_ui.Forget();
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
      m_guard.Apply(cfg.hideOneClick, cfg.hotkeys);
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
         // The Enter that finished typing in a field must not also confirm the order.
         if(cmd == AI_CMD_CONFIRM && AiNowMs() - m_lastEndEdit < 500)
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
      m_guard.LockScroll(m_dragPanel || m_panel.Contains(mx, my));
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
         if(m_lineDrag)
           {
            m_lineDrag = false;
            m_lines.EndDrag();
            Refresh(true);
           }
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
             IntegerToString(m_panel.x) + "," + IntegerToString(m_panel.y) + "," + IntegerToString(cw) + "," + IntegerToString(ch);
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
      ComposeView(m_view);
      string sig = ViewSignature(cw, ch);
      if(force || sig != m_lastSig)
        {
         m_lastSig = sig;
         m_ui.BeginFrame();
         m_panel.Render(m_view, m_theme, m_ui);
         m_ui.EndFrame();
         m_refreshEdits = false;
        }
      bool show = (m_phase == AI_PHASE_PREVIEW || m_phase == AI_PHASE_SENDING ||
                   (m_phase == AI_PHASE_COOLDOWN && m_afterCooldown == AI_PHASE_PREVIEW));
      bool tagsLeft = (m_panel.x + m_panel.w / 2 > cw / 2);
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
      Draw(force);
     }

   void              Exec(const ENUM_AI_CMD cmd)
     {
      if(cmd == AI_CMD_NONE)
         return;
      if(m_phase == AI_PHASE_SENDING || m_phase == AI_PHASE_COOLDOWN || m_pinStep != 0)
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
      m_lastMove = 0;
      m_pinStep = 0;
      m_pinName = "";
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
      m_guard.Apply(cfg.hideOneClick, cfg.hotkeys);
      m_lastShift = -1.0;

      // Lines and tags first, so the panel created after them is drawn on top.
      ObjectsDeleteAll(0, AI_OBJ_PREFIX);
      m_ui.Forget();
      MqlTick tick;
      m_lines.Create((SymbolInfoTick(_Symbol, tick) && tick.bid > 0.0) ? tick.bid : 1.0);
      m_lastSig = "";
      m_mouseDown = false;
      m_dragPanel = false;
      m_lineDrag = false;
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
