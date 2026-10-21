//+------------------------------------------------------------------+
//| ActionInna - shared constants, enums and data structures         |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_DEFINES_MQH
#define ACTIONINNA_DEFINES_MQH

#define AI_NAME           "ActionInna"
#define AI_FILES_DIR      "ActionInna"
#define AI_TEMPLATE_NAME  "ActionInna-panel"
#define AI_MEM_MAX        10

// Every object ActionInna draws starts with AI_OBJ_PREFIX. It is unusual on purpose: cleaning up
// deletes everything with this prefix, and must never take another tool's objects with it.
#define AI_OBJ_PREFIX     "AINNA_"
#define AI_P              "AINNA_P_"
#define AI_L              "AINNA_L_"
#define AI_T              "AINNA_T_"
#define AI_Z              "AINNA_Z_"

// Sides are signed so a level can be written as entry - side * distance.
#define AI_BUY            1
#define AI_SELL           -1

// Result codes of AiLotsForRisk.
#define AI_LOTS_OK        0
#define AI_LOTS_NO_RISK   1
#define AI_LOTS_NO_VALUE  2
#define AI_LOTS_BELOW_MIN 3
#define AI_LOTS_CAPPED    4

// Hotkey slots.
#define AI_KEY_BUY        0
#define AI_KEY_SELL       1
#define AI_KEY_CONFIRM    2
#define AI_KEY_CANCEL     3
#define AI_KEY_RISK1      4
#define AI_KEY_RISK2      5
#define AI_KEY_RISK3      6
#define AI_KEY_RISKC      7
#define AI_KEY_RECALL     8
#define AI_KEY_PENDING    9
#define AI_KEY_COLLAPSE   10
#define AI_KEY_COUNT      11

enum ENUM_AI_PIP_MODE
  {
   AI_PIP_TRADER = 0, // Trader: gold 0.1, 3/5-digit symbols 10 points, others 1 point
   AI_PIP_EXNESS = 1, // Exness: 1 pip = 10 points on every symbol
   AI_PIP_POINT  = 2  // Points: 1 pip = 1 point
  };

enum ENUM_AI_RISK_BASE
  {
   AI_BASE_EQUITY  = 0, // Equity (as in Exness)
   AI_BASE_BALANCE = 1  // Balance
  };

enum ENUM_AI_RISK_MODE
  {
   AI_RISK_PERCENT = 0, // Percent of equity or balance
   AI_RISK_MONEY   = 1, // Amount in account currency
   AI_RISK_LOTS    = 2  // Fixed lots
  };

enum ENUM_AI_LEVEL_MODE
  {
   AI_LEVEL_PIPS  = 0, // Pips
   AI_LEVEL_PRICE = 1, // Price
   AI_LEVEL_RR    = 2  // R multiple of the stop (take profit only)
  };

enum ENUM_AI_THEME
  {
   AI_THEME_AUTO  = 0, // Auto (follows the chart background)
   AI_THEME_DARK  = 1, // Dark
   AI_THEME_LIGHT = 2  // Light
  };

enum ENUM_AI_PHASE
  {
   AI_PHASE_IDLE = 0,
   AI_PHASE_PREVIEW,
   AI_PHASE_SENDING,
   AI_PHASE_COOLDOWN
  };

enum ENUM_AI_CMD
  {
   AI_CMD_NONE = 0,
   AI_CMD_BUY,
   AI_CMD_SELL,
   AI_CMD_CONFIRM,
   AI_CMD_CANCEL,
   AI_CMD_RISK1,
   AI_CMD_RISK2,
   AI_CMD_RISK3,
   AI_CMD_RISKC,
   AI_CMD_RISK_UNIT,
   AI_CMD_SL_MODE,
   AI_CMD_TP_MODE,
   AI_CMD_SL_RECALL,
   AI_CMD_TP_RECALL,
   AI_CMD_RECALL,
   AI_CMD_KIND,
   AI_CMD_MENU,
   AI_CMD_COLLAPSE,
   AI_CMD_OPT_AUTO,
   AI_CMD_OPT_ONECLICK,
   AI_CMD_OPT_BASE,
   AI_CMD_PIN,
   AI_CMD_TEMPLATE,
   AI_CMD_RISK_NEXT
  };

// Settings copied from the EA inputs (inputs themselves are read-only).
struct AiSettings
  {
   double            preset[3];
   ENUM_AI_RISK_BASE riskBase;
   double            maxRiskPct;
   double            commissionRT;
   bool              requireSL;
   bool              requireTP;
   double            defaultSLPips;
   ENUM_AI_LEVEL_MODE defaultTPMode;
   double            defaultTPValue;
   ENUM_AI_PIP_MODE  pipMode;
   bool              autoRecall;
   double            pendingOffsetPips;
   bool              oneClick;
   ulong             magic;
   int               deviation;
   string            comment;
   bool              hotkeys;
   string            keyBuy;
   string            keySell;
   string            keyConfirm;
   string            keyCancel;
   string            keyRisk1;
   string            keyRisk2;
   string            keyRisk3;
   string            keyRiskC;
   string            keyRecall;
   string            keyPending;
   string            keyCollapse;
   bool              hideOneClick;
   bool              autoShift;
   bool              showZones;
   ENUM_AI_THEME     theme;
   double            uiScale;
   string            font;
   int               fontSize;
   bool              sounds;
   bool              debugLog;
  };

// What the trader entered. Values are in the unit of their mode.
struct AiInput
  {
   int               side;
   bool              pending;
   double            entry;
   int               slMode;
   double            slValue;
   int               tpMode;
   double            tpValue;
   int               riskMode;
   double            riskValue;
   int               riskBase;
  };

// The order that would be sent, with everything the panel shows about it.
struct AiPlan
  {
   bool              valid;        // every check passed: CONFIRM may send it
   bool              noData;       // prices or symbol data have not arrived yet
   string            err;          // first blocking problem
   string            warn;         // note that does not block
   int               side;
   bool              pending;
   ENUM_ORDER_TYPE   type;
   double            entry;
   double            sl;           // 0 = none
   double            tp;           // 0 = none
   double            lots;
   double            riskMoney;    // loss at the stop, commission included
   double            riskPct;
   double            rewardMoney;  // gain at the target, commission deducted
   double            rewardPct;
   double            rr;           // target distance / stop distance
   double            slPips;
   double            tpPips;
   double            pipValue;     // money per pip for 'lots'
   double            margin;
   double            freeAfter;
   double            units;
   double            spreadPips;
   double            commission;   // round turn for 'lots'
   double            base;         // equity or balance the % is measured on
   double            bid;
   double            ask;
  };

// One remembered SL/TP. Distances are stored as price, not points or pips: a $5 stop on gold is
// $5 at every broker, while its count in points depends on how many digits the broker quotes.
struct AiMem
  {
   long              t;
   int               side;
   int               slMode;
   double            slDist;
   double            slPrice;
   int               tpMode;
   double            tpDist;
   double            tpPrice;
   double            tpR;
  };

#endif
