//+------------------------------------------------------------------+
//| ActionInna.mq5                                                   |
//| Exness-style risk trade panel for MetaTrader 5 desktop           |
//+------------------------------------------------------------------+
#property copyright   "ActionInna, MIT licence"
#property link        "https://github.com/deaguss/action-inna-panelmt5"
#property version     "1.00"
#property description "Risk trade panel: 1% / 1.5% / 2% / custom risk presets, SL/TP in pips, price or R,"
#property description "a chart preview before anything is sent, and recall of the SL/TP you used before."

#include <ActionInna\App.mqh>

input group "Risk"
input double              InpRisk1          = 1.0;            // Risk preset 1 (%)
input double              InpRisk2          = 1.5;            // Risk preset 2 (%)
input double              InpRisk3          = 2.0;            // Risk preset 3 (%)
input ENUM_AI_RISK_BASE   InpRiskBase       = AI_BASE_EQUITY; // Risk % is measured on
input double              InpMaxRiskPct     = 5.0;            // Safety cap: block orders risking more than (%)
input double              InpCommissionRT   = 0.0;            // Commission per lot, round turn, in account currency

input group "Stop loss and take profit"
input bool                InpRequireSL      = true;           // Require a stop loss
input bool                InpRequireTP      = true;           // Require a take profit
input double              InpDefaultSLPips  = 20.0;           // Default stop loss (pips)
input ENUM_AI_LEVEL_MODE  InpDefaultTPMode  = AI_LEVEL_RR;    // Default take profit mode
input double              InpDefaultTPValue = 2.0;            // Default take profit (R multiple or pips)
input ENUM_AI_PIP_MODE    InpPipMode        = AI_PIP_TRADER;  // Pip convention
input bool                InpAutoRecall     = true;           // Set SL/TP automatically from your last trade on the symbol
input double              InpPendingOffset  = 10.0;           // A new pending order starts this many pips from the market

input group "Execution"
input bool                InpOneClick       = false;          // One-click trading: SELL/BUY send at once, no preview
input ulong               InpMagic          = 0;              // Magic number (0 = counts as a manual trade)
input int                 InpDeviation      = 10;             // Max slippage in points (instant and request execution only)
input ENUM_AI_SLIP        InpAfterSlip      = AI_SLIP_FOLLOW; // When a market order fills at another price
input string              InpComment        = "ActionInna";   // Order comment
input bool                InpManageOrders   = true;           // Drag open trades' entry/SL/TP with a confirm pop-up (replaces MT5's own trade lines on this chart)

input group "Hotkeys (the chart must have focus)"
input bool                InpHotkeys        = true;           // Enable hotkeys
input string              InpKeyBuy         = "B";            // Preview BUY
input string              InpKeySell        = "S";            // Preview SELL
input string              InpKeyConfirm     = "ENTER";        // Confirm the previewed order
input string              InpKeyCancel      = "ESC";          // Close the preview
input string              InpKeyRisk1       = "1";            // Risk preset 1
input string              InpKeyRisk2       = "2";            // Risk preset 2
input string              InpKeyRisk3       = "3";            // Risk preset 3
input string              InpKeyRiskCustom  = "4";            // Custom risk
input string              InpKeyRecall      = "R";            // Recall earlier SL/TP (press again for older ones)
input string              InpKeyPending     = "P";            // Switch Market / Pending
input string              InpKeyCollapse    = "H";            // Collapse / expand the panel

input group "Display"
input bool                InpHideOneClick   = true;           // Hide MT5's One-Click panel while ActionInna runs
input bool                InpAutoShift      = true;           // Shift the chart so the panel does not cover candles
input bool                InpShowZones      = true;           // Shade the risk and reward zones
input ENUM_AI_THEME       InpTheme          = AI_THEME_AUTO;  // Theme
input double              InpUiScale        = 1.0;            // Panel scale (1.0 follows the Windows display scale)
input string              InpFont           = "Arial";        // Font (Arial is on every Windows PC, so text keeps the layout's sizes)
input int                 InpFontSize       = 9;              // Font size
input bool                InpSounds         = true;           // Play a sound when an order is sent or refused
input bool                InpDebugLog       = true;           // Write a log to MQL5\Files\ActionInna\log.txt

CAiApp g_app;

int OnInit()
  {
   g_app.cfg.preset[0] = InpRisk1;
   g_app.cfg.preset[1] = InpRisk2;
   g_app.cfg.preset[2] = InpRisk3;
   g_app.cfg.riskBase = InpRiskBase;
   g_app.cfg.maxRiskPct = InpMaxRiskPct;
   g_app.cfg.commissionRT = InpCommissionRT;
   g_app.cfg.requireSL = InpRequireSL;
   g_app.cfg.requireTP = InpRequireTP;
   g_app.cfg.defaultSLPips = InpDefaultSLPips;
   g_app.cfg.defaultTPMode = InpDefaultTPMode;
   g_app.cfg.defaultTPValue = InpDefaultTPValue;
   g_app.cfg.pipMode = InpPipMode;
   g_app.cfg.autoRecall = InpAutoRecall;
   g_app.cfg.pendingOffsetPips = InpPendingOffset;
   g_app.cfg.oneClick = InpOneClick;
   g_app.cfg.magic = InpMagic;
   g_app.cfg.deviation = InpDeviation;
   g_app.cfg.slipPolicy = InpAfterSlip;
   g_app.cfg.comment = InpComment;
   g_app.cfg.manageOrders = InpManageOrders;
   g_app.cfg.hotkeys = InpHotkeys;
   g_app.cfg.keyBuy = InpKeyBuy;
   g_app.cfg.keySell = InpKeySell;
   g_app.cfg.keyConfirm = InpKeyConfirm;
   g_app.cfg.keyCancel = InpKeyCancel;
   g_app.cfg.keyRisk1 = InpKeyRisk1;
   g_app.cfg.keyRisk2 = InpKeyRisk2;
   g_app.cfg.keyRisk3 = InpKeyRisk3;
   g_app.cfg.keyRiskC = InpKeyRiskCustom;
   g_app.cfg.keyRecall = InpKeyRecall;
   g_app.cfg.keyPending = InpKeyPending;
   g_app.cfg.keyCollapse = InpKeyCollapse;
   g_app.cfg.hideOneClick = InpHideOneClick;
   g_app.cfg.autoShift = InpAutoShift;
   g_app.cfg.showZones = InpShowZones;
   g_app.cfg.theme = InpTheme;
   g_app.cfg.uiScale = InpUiScale;
   g_app.cfg.font = InpFont;
   g_app.cfg.fontSize = InpFontSize;
   g_app.cfg.sounds = InpSounds;
   g_app.cfg.debugLog = InpDebugLog;
   return g_app.Init();
  }

void OnDeinit(const int reason)
  {
   g_app.Deinit(reason);
  }

void OnTick()
  {
   g_app.Tick();
  }

void OnTimer()
  {
   g_app.Timer();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   g_app.ChartEvent(id, lparam, dparam, sparam);
  }
//+------------------------------------------------------------------+
