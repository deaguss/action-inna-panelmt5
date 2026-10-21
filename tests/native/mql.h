// A stand-in for MQL5, so ActionInna's own sources compile with g++ and run on any PC:
// MQL5's types, strings and checked dynamic arrays, the built-in functions the sources call, and a
// fake terminal (chart objects, one symbol, an account, and a trade server that records requests).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <cmath>
#include <string>
#include <vector>
#include <deque>
#include <map>
#include <functional>
#include <algorithm>
#include <type_traits>
#include <float.h>
#include <fenv.h>

typedef uint64_t ulong;
typedef uint32_t uint;
typedef uint16_t ushort;
typedef uint8_t uchar;
typedef int64_t datetime;
typedef uint32_t color;

//--- string -------------------------------------------------------------
struct string
  {
   std::string s;
   string() {}
   string(const char *c) : s(c ? c : "") {}
   string(const std::string &x) : s(x) {}
   string &operator+=(const string &o) { s += o.s; return *this; }
  };
inline string operator+(const string &a, const string &b) { return string(a.s + b.s); }
inline bool operator==(const string &a, const string &b) { return a.s == b.s; }
inline bool operator!=(const string &a, const string &b) { return a.s != b.s; }
inline bool operator<(const string &a, const string &b) { return a.s < b.s; }

//--- dynamic arrays: every index is checked, as MQL5 does ---------------
[[noreturn]] inline void MqlCrash(const char *what)
  {
   fprintf(stderr, "\n*** MQL5 runtime error: %s ***\n", what);
   fflush(stderr);
   std::abort();
  }

template<class T> struct MqlArray
  {
   std::deque<T> v;   // a deque, because vector<bool> hands out no bool&
   T &operator[](int i) { if(i < 0 || i >= (int)v.size()) MqlCrash("array out of range"); return v[i]; }
   const T &operator[](int i) const { if(i < 0 || i >= (int)v.size()) MqlCrash("array out of range"); return v[i]; }
  };
template<class T> int ArraySize(const MqlArray<T> &a) { return (int)a.v.size(); }
template<class T, size_t N> int ArraySize(const T (&)[N]) { return (int)N; }
template<class T> int ArrayResize(MqlArray<T> &a, int n, int reserve = 0) { if(n < 0) return -1; (void)reserve; a.v.resize(n); return n; }
template<class T, size_t N, class V> int ArrayInitialize(T (&a)[N], V val) { for(auto &x : a) x = (T)val; return (int)N; }
template<class T> void ZeroMemory(T &x) { x = T(); }

//--- maths ---------------------------------------------------------------
template<class A, class B> typename std::common_type<A, B>::type MathMax(A a, B b) { return a > b ? a : b; }
template<class A, class B> typename std::common_type<A, B>::type MathMin(A a, B b) { return a < b ? a : b; }
template<class T> T MathAbs(T v) { return v < 0 ? -v : v; }
inline double MathRound(double v) { return std::round(v); }
inline double MathFloor(double v) { return std::floor(v); }
inline double MathPow(double a, double b) { return std::pow(a, b); }
inline bool MathIsValidNumber(double v) { return std::isfinite(v); }
inline double NormalizeDouble(double v, int digits) { double p = std::pow(10.0, digits); return std::round(v * p) / p; }

//--- strings -------------------------------------------------------------
inline string DoubleToString(double v, int digits = 8)
  {
   if(digits < 0 || digits > 16)
      digits = 8;
   char b[512];
   snprintf(b, sizeof b, "%.*f", digits, v);
   return string(b);
  }
inline string IntegerToString(int64_t v, int len = 0, ushort fill = ' ')
  {
   std::string r = std::to_string(v);
   while((int)r.size() < len)
      r.insert(r.begin(), (char)fill);
   return string(r);
  }
inline int64_t StringToInteger(const string &s) { return strtoll(s.s.c_str(), nullptr, 10); }
inline double StringToDouble(const string &s) { return strtod(s.s.c_str(), nullptr); }
inline int StringLen(const string &s) { return (int)s.s.size(); }
inline int StringFind(const string &s, const string &sub, int start = 0)
  {
   if(start < 0)
      start = 0;
   if(start > (int)s.s.size())
      return -1;
   size_t p = s.s.find(sub.s, (size_t)start);
   return (p == std::string::npos) ? -1 : (int)p;
  }
inline string StringSubstr(const string &s, int start, int len = -1)
  {
   if(start < 0 || start >= (int)s.s.size())
      return string();
   return string(len < 0 ? s.s.substr(start) : s.s.substr(start, len));
  }
inline ushort StringGetCharacter(const string &s, int pos) { return (pos < 0 || pos >= (int)s.s.size()) ? 0 : (uchar)s.s[pos]; }
inline int StringReplace(string &s, const string &find, const string &rep)
  {
   if(find.s.empty())
      return -1;
   int n = 0;
   size_t p = 0;
   while((p = s.s.find(find.s, p)) != std::string::npos)
     {
      s.s.replace(p, find.s.size(), rep.s);
      p += rep.s.size();
      n++;
     }
   return n;
  }
inline bool MqlSpace(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
inline int StringTrimLeft(string &s) { size_t i = 0; while(i < s.s.size() && MqlSpace(s.s[i])) i++; s.s.erase(0, i); return (int)i; }
inline int StringTrimRight(string &s) { size_t n = 0; while(!s.s.empty() && MqlSpace(s.s.back())) { s.s.pop_back(); n++; } return (int)n; }
inline bool StringToUpper(string &s) { for(auto &c : s.s) c = (char)toupper((unsigned char)c); return true; }
inline bool StringToLower(string &s) { for(auto &c : s.s) c = (char)tolower((unsigned char)c); return true; }
inline int StringSplit(const string &s, ushort sep, MqlArray<string> &out)
  {
   out.v.clear();
   if(s.s.empty())
      return 0;
   std::string cur;
   for(char c : s.s)
     {
      if((ushort)(uchar)c == sep)
        {
         out.v.push_back(string(cur));
         cur.clear();
        }
      else
         cur += c;
     }
   out.v.push_back(string(cur));
   return (int)out.v.size();
  }
inline string ShortToString(ushort c) { return string(std::string(1, (char)c)); }

//--- MT5 constants ---------------------------------------------------------
#define AI_RGB(r, g, b) ((color)((r) | ((g) << 8) | ((b) << 16)))
const color clrWhite = 0xFFFFFF;
const color clrGray = 0x808080;
const int INVALID_HANDLE = -1;
const int INIT_SUCCEEDED = 0;
const int IDOK = 1, IDCANCEL = 2;
const int MB_OKCANCEL = 1, MB_ICONQUESTION = 0x20, MB_ICONEXCLAMATION = 0x30;
const int FW_NORMAL = 400, FW_BOLD = 700;
const int TIME_DATE = 1, TIME_MINUTES = 2, TIME_SECONDS = 4;
const int REASON_REMOVE = 1, REASON_CHARTCHANGE = 3, REASON_PARAMETERS = 5;
const int FILE_READ = 1, FILE_WRITE = 2, FILE_TXT = 16, FILE_ANSI = 32, FILE_SHARE_READ = 128, FILE_SHARE_WRITE = 256,
          FILE_REWRITE = 512, FILE_COMMON = 4096;

enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL, ORDER_TYPE_BUY_LIMIT, ORDER_TYPE_SELL_LIMIT, ORDER_TYPE_BUY_STOP,
                       ORDER_TYPE_SELL_STOP, ORDER_TYPE_BUY_STOP_LIMIT, ORDER_TYPE_SELL_STOP_LIMIT, ORDER_TYPE_CLOSE_BY };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC, ORDER_TIME_DAY, ORDER_TIME_SPECIFIED, ORDER_TIME_SPECIFIED_DAY };
enum ENUM_TRADE_REQUEST_ACTIONS { TRADE_ACTION_DEAL = 1, TRADE_ACTION_PENDING = 5, TRADE_ACTION_SLTP = 6, TRADE_ACTION_MODIFY = 7,
                                  TRADE_ACTION_REMOVE = 8 };
const uint TRADE_RETCODE_REQUOTE = 10004, TRADE_RETCODE_PLACED = 10008, TRADE_RETCODE_DONE = 10009, TRADE_RETCODE_DONE_PARTIAL = 10010,
           TRADE_RETCODE_INVALID = 10013, TRADE_RETCODE_INVALID_STOPS = 10016, TRADE_RETCODE_PRICE_CHANGED = 10020,
           TRADE_RETCODE_PRICE_OFF = 10021, TRADE_RETCODE_NO_CHANGES = 10025, TRADE_RETCODE_INVALID_FILL = 10030;

enum { SYMBOL_DIGITS = 1, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_TRADE_MODE, SYMBOL_TRADE_EXEMODE, SYMBOL_FILLING_MODE,
       SYMBOL_ORDER_MODE, SYMBOL_EXPIRATION_MODE };
enum ENUM_SYMBOL_INFO_DOUBLE { SYMBOL_POINT = 101, SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_CONTRACT_SIZE, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX,
                               SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_LIMIT, SYMBOL_TRADE_TICK_VALUE, SYMBOL_TRADE_TICK_VALUE_LOSS,
                               SYMBOL_TRADE_TICK_VALUE_PROFIT };
const int SYMBOL_TRADE_MODE_DISABLED = 0, SYMBOL_TRADE_MODE_LONGONLY = 1, SYMBOL_TRADE_MODE_SHORTONLY = 2, SYMBOL_TRADE_MODE_CLOSEONLY = 3,
          SYMBOL_TRADE_MODE_FULL = 4;
const int SYMBOL_TRADE_EXECUTION_REQUEST = 0, SYMBOL_TRADE_EXECUTION_INSTANT = 1, SYMBOL_TRADE_EXECUTION_MARKET = 2;
const int SYMBOL_FILLING_FOK = 1, SYMBOL_FILLING_IOC = 2;
const int SYMBOL_ORDER_MARKET = 1, SYMBOL_ORDER_LIMIT = 2, SYMBOL_ORDER_STOP = 4, SYMBOL_ORDER_STOP_LIMIT = 8, SYMBOL_ORDER_SL = 16,
          SYMBOL_ORDER_TP = 32, SYMBOL_ORDER_CLOSEBY = 64;
const int SYMBOL_EXPIRATION_GTC = 1, SYMBOL_EXPIRATION_DAY = 2, SYMBOL_EXPIRATION_SPECIFIED = 4, SYMBOL_EXPIRATION_SPECIFIED_DAY = 8;

enum { ACCOUNT_BALANCE = 201, ACCOUNT_EQUITY, ACCOUNT_MARGIN_FREE };
enum { ACCOUNT_MARGIN_MODE = 211, ACCOUNT_TRADE_ALLOWED, ACCOUNT_TRADE_EXPERT };
enum { ACCOUNT_CURRENCY = 221, ACCOUNT_SERVER };
const int ACCOUNT_MARGIN_MODE_RETAIL_NETTING = 0, ACCOUNT_MARGIN_MODE_EXCHANGE = 1, ACCOUNT_MARGIN_MODE_RETAIL_HEDGING = 2;
enum ENUM_TERMINAL_INFO_INTEGER { TERMINAL_BUILD = 301, TERMINAL_CONNECTED, TERMINAL_TRADE_ALLOWED, TERMINAL_SCREEN_DPI,
                                  TERMINAL_KEYSTATE_SHIFT, TERMINAL_KEYSTATE_CONTROL };
enum ENUM_TERMINAL_INFO_STRING { TERMINAL_DATA_PATH = 311 };
enum { MQL_TESTER = 321, MQL_TRADE_ALLOWED };

enum { POSITION_TYPE = 401, POSITION_TIME_MSC };
enum { POSITION_VOLUME = 411, POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP, POSITION_PROFIT, POSITION_SWAP };
enum { POSITION_SYMBOL = 421 };
const int POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1;
enum { ORDER_TYPE = 431, ORDER_TYPE_TIME, ORDER_TIME_EXPIRATION };
enum { ORDER_VOLUME_CURRENT = 441, ORDER_PRICE_OPEN, ORDER_SL, ORDER_TP, ORDER_PRICE_STOPLIMIT };
enum { ORDER_SYMBOL = 451 };
enum { DEAL_ENTRY = 461, DEAL_TYPE, DEAL_ORDER, DEAL_TIME };
enum { DEAL_PRICE = 471 };
enum { DEAL_SYMBOL = 481 };
const int DEAL_ENTRY_IN = 0, DEAL_TYPE_BUY = 0, DEAL_TYPE_SELL = 1;

enum { CHART_SHOW_ONE_CLICK = 501, CHART_QUICK_NAVIGATION, CHART_EVENT_MOUSE_MOVE, CHART_MOUSE_SCROLL, CHART_SHIFT, CHART_SHOW_TRADE_LEVELS,
       CHART_DRAG_TRADE_LEVELS, CHART_WIDTH_IN_PIXELS, CHART_HEIGHT_IN_PIXELS, CHART_COLOR_BACKGROUND };
enum { CHART_SHIFT_SIZE = 521 };
enum { CHARTEVENT_KEYDOWN = 0, CHARTEVENT_OBJECT_CLICK = 1, CHARTEVENT_OBJECT_DRAG = 2, CHARTEVENT_OBJECT_ENDEDIT = 3,
       CHARTEVENT_CHART_CHANGE = 9, CHARTEVENT_MOUSE_MOVE = 10 };

enum { OBJ_HLINE = 1, OBJ_RECTANGLE, OBJ_LABEL, OBJ_RECTANGLE_LABEL, OBJ_EDIT };
enum { OBJPROP_COLOR = 601, OBJPROP_STYLE, OBJPROP_WIDTH, OBJPROP_BACK, OBJPROP_SELECTABLE, OBJPROP_SELECTED, OBJPROP_HIDDEN,
       OBJPROP_ZORDER, OBJPROP_TIMEFRAMES, OBJPROP_CORNER, OBJPROP_BORDER_TYPE, OBJPROP_ANCHOR, OBJPROP_XDISTANCE, OBJPROP_YDISTANCE,
       OBJPROP_XSIZE, OBJPROP_YSIZE, OBJPROP_BGCOLOR, OBJPROP_FONTSIZE, OBJPROP_FILL, OBJPROP_READONLY, OBJPROP_ALIGN,
       OBJPROP_BORDER_COLOR, OBJPROP_TIME };
enum { OBJPROP_PRICE = 651 };
enum { OBJPROP_TEXT = 661, OBJPROP_TOOLTIP, OBJPROP_FONT };
const int64_t OBJ_ALL_PERIODS = 0x1FFFFF, OBJ_NO_PERIODS = -1;
const int CORNER_LEFT_UPPER = 0, BORDER_FLAT = 0, ALIGN_RIGHT = 2;
enum ENUM_ANCHOR_POINT { ANCHOR_LEFT_UPPER, ANCHOR_LEFT, ANCHOR_LEFT_LOWER, ANCHOR_LOWER, ANCHOR_RIGHT_LOWER, ANCHOR_RIGHT,
                         ANCHOR_RIGHT_UPPER, ANCHOR_UPPER, ANCHOR_CENTER };
enum ENUM_LINE_STYLE { STYLE_SOLID, STYLE_DASH, STYLE_DOT };

//--- MT5 structures --------------------------------------------------------
struct MqlTick
  {
   datetime time;
   double bid, ask, last;
   ulong volume;
   int64_t time_msc;
   uint flags;
   double volume_real;
  };
struct MqlTradeRequest
  {
   ENUM_TRADE_REQUEST_ACTIONS action;
   ulong magic, order;
   string symbol;
   double volume, price, stoplimit, sl, tp;
   ulong deviation;
   ENUM_ORDER_TYPE type;
   ENUM_ORDER_TYPE_FILLING type_filling;
   ENUM_ORDER_TYPE_TIME type_time;
   datetime expiration;
   string comment;
   ulong position, position_by;
  };
struct MqlTradeResult
  {
   uint retcode;
   ulong deal, order;
   double volume, price, bid, ask;
   string comment;
   uint request_id;
   int retcode_external;
  };

//--- the fake terminal -------------------------------------------------------
struct FakeObj
  {
   int type = 0;
   int order = 0;                           // creation order: MT5 draws later objects on top
   std::map<int, int64_t> i;
   std::map<int, double> d;                 // key: prop * 16 + modifier
   std::map<int, std::string> s;
  };
struct FakePos { ulong ticket; int type; double volume, open, sl, tp, swap; int64_t timeMsc; std::string symbol; };
struct FakeOrd { ulong ticket; int type; double volume, price, sl, tp, stoplimit; int typeTime; datetime expiration; std::string symbol; };
struct FakeSym
  {
   std::string name = "EURUSD";
   int digits = 5;
   double point = 0.00001, tickSize = 0.00001, contract = 100000, tickValue = 1.0;
   double volMin = 0.01, volMax = 100.0, volStep = 0.01, volLimit = 0.0;
   int stops = 0, freeze = 0, tradeMode = SYMBOL_TRADE_MODE_FULL, exeMode = SYMBOL_TRADE_EXECUTION_MARKET;
   int filling = 3, orderMode = 127, expiration = 15;
   double bid = 1.08480, ask = 1.08500;
  };
struct FakeFile { std::string data; size_t pos = 0; std::string key; };

struct Fake
  {
   ulong us = 10000000000ULL;               // GetMicrosecondCount
   datetime time = 1792000000;
   int chartW = 1200, chartH = 700;
   color chartBg = 0;
   double top = 0.0, bottom = 0.0;          // prices at the top and bottom of the chart; 0 = 1% around the bid
   std::map<int, int64_t> chartI;
   std::map<int, double> chartD;
   std::map<std::string, FakeObj> objs;
   int objSeq = 0;
   FakeSym sym;
   double balance = 10000.0, equity = 10000.0, marginFree = 10000.0;
   int marginMode = ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   std::string currency = "USD";
   bool connected = true, termTrade = true, mqlTrade = true, accTrade = true, accExpert = true;
   std::vector<FakePos> pos;
   std::vector<FakeOrd> ords;
   int selPos = -1, selOrd = -1;
   ulong nextTicket = 900000;
   std::vector<MqlTradeRequest> requests;
   uint forceRetcode = 0;                   // 0 = the server applies the request
   std::function<void(const MqlTradeRequest &)> onSend;   // checks a request before the server applies it
   int lastError = 0;
   int messageBoxAnswer = IDOK;
   int fontSize = 90;
   std::vector<std::string> templates;
   int64_t levelsAtSave = -99;
   std::map<std::string, std::string> files;
   std::map<int, FakeFile> handles;
   int nextHandle = 1;
   bool quiet = true;
   std::vector<std::string> printed;

   void Reset()
     {
      ulong keepUs = us;
      auto keepOnSend = onSend;
      bool keepQuiet = quiet;
      *this = Fake();
      us = keepUs + 1000000;
      onSend = keepOnSend;
      quiet = keepQuiet;
      chartI[CHART_SHOW_ONE_CLICK] = 1;
      chartI[CHART_QUICK_NAVIGATION] = 1;
      chartI[CHART_EVENT_MOUSE_MOVE] = 0;
      chartI[CHART_MOUSE_SCROLL] = 1;
      chartI[CHART_SHIFT] = 0;
      chartI[CHART_SHOW_TRADE_LEVELS] = 1;
      chartI[CHART_DRAG_TRADE_LEVELS] = 1;
      chartD[CHART_SHIFT_SIZE] = 10.0;
     }
  };
inline Fake g_fake;
inline string _Symbol = string("EURUSD");
inline int _Period = 1;

inline void FakeRange(double &top, double &bottom)
  {
   if(g_fake.top > g_fake.bottom)
     {
      top = g_fake.top;
      bottom = g_fake.bottom;
      return;
     }
   top = g_fake.sym.bid * 1.01;
   bottom = g_fake.sym.bid * 0.99;
  }

//--- output ----------------------------------------------------------------
inline std::string MqlText(const string &v) { return v.s; }
inline std::string MqlText(const char *v) { return v; }
inline std::string MqlText(double v) { char b[64]; snprintf(b, sizeof b, "%.8g", v); return b; }
template<class T> std::string MqlText(const T &v) { return std::to_string(v); }
template<class... A> void Print(const A &... a)
  {
   std::string r;
   ((r += MqlText(a)), ...);
   g_fake.printed.push_back(r);
   if(!g_fake.quiet)
      puts(r.c_str());
  }
template<class... A> void Alert(const A &... a) { Print(a...); }

//--- time, errors, environment -----------------------------------------------
inline ulong GetMicrosecondCount() { return g_fake.us; }
inline datetime TimeCurrent() { return g_fake.time; }
inline datetime TimeLocal() { return g_fake.time; }
inline string TimeToString(datetime, int = TIME_DATE | TIME_MINUTES) { return string("2026.10.21 12:00:00"); }
inline datetime iTime(const string &, int, int) { return g_fake.time; }
inline int PeriodSeconds(int = 0) { return 60; }
inline void Sleep(int) {}
inline int GetLastError() { return g_fake.lastError; }
inline void ResetLastError() { g_fake.lastError = 0; }
inline bool EventSetMillisecondTimer(int) { return true; }
inline void EventKillTimer() {}
inline bool PlaySound(const string &) { return true; }
inline int MessageBox(const string &, const string & = string(""), int = 0) { return g_fake.messageBoxAnswer; }
inline int64_t MQLInfoInteger(int prop) { return prop == MQL_TRADE_ALLOWED ? (g_fake.mqlTrade ? 1 : 0) : 0; }
inline int64_t TerminalInfoInteger(ENUM_TERMINAL_INFO_INTEGER prop)
  {
   switch(prop)
     {
      case TERMINAL_BUILD: return 5000;
      case TERMINAL_CONNECTED: return g_fake.connected ? 1 : 0;
      case TERMINAL_TRADE_ALLOWED: return g_fake.termTrade ? 1 : 0;
      case TERMINAL_SCREEN_DPI: return 96;
      default: return 0;
     }
  }
inline string TerminalInfoString(ENUM_TERMINAL_INFO_STRING) { return string("C:\\FakeTerminal"); }
inline double AccountInfoDouble(int prop)
  {
   if(prop == ACCOUNT_BALANCE) return g_fake.balance;
   if(prop == ACCOUNT_EQUITY) return g_fake.equity;
   if(prop == ACCOUNT_MARGIN_FREE) return g_fake.marginFree;
   return 0.0;
  }
inline int64_t AccountInfoInteger(int prop)
  {
   if(prop == ACCOUNT_MARGIN_MODE) return g_fake.marginMode;
   if(prop == ACCOUNT_TRADE_ALLOWED) return g_fake.accTrade ? 1 : 0;
   if(prop == ACCOUNT_TRADE_EXPERT) return g_fake.accExpert ? 1 : 0;
   return 0;
  }
inline string AccountInfoString(int prop) { return string(prop == ACCOUNT_CURRENCY ? g_fake.currency : std::string("FakeServer")); }

//--- symbol ----------------------------------------------------------------
inline int64_t SymbolInfoInteger(const string &symbol, int prop)
  {
   const FakeSym &s = g_fake.sym;
   if(symbol.s != s.name) return 0;
   switch(prop)
     {
      case SYMBOL_DIGITS: return s.digits;
      case SYMBOL_TRADE_STOPS_LEVEL: return s.stops;
      case SYMBOL_TRADE_FREEZE_LEVEL: return s.freeze;
      case SYMBOL_TRADE_MODE: return s.tradeMode;
      case SYMBOL_TRADE_EXEMODE: return s.exeMode;
      case SYMBOL_FILLING_MODE: return s.filling;
      case SYMBOL_ORDER_MODE: return s.orderMode;
      case SYMBOL_EXPIRATION_MODE: return s.expiration;
     }
   return 0;
  }
inline double SymbolInfoDouble(const string &symbol, int prop)
  {
   const FakeSym &s = g_fake.sym;
   if(symbol.s != s.name) return 0.0;
   switch(prop)
     {
      case SYMBOL_POINT: return s.point;
      case SYMBOL_TRADE_TICK_SIZE: return s.tickSize;
      case SYMBOL_TRADE_CONTRACT_SIZE: return s.contract;
      case SYMBOL_VOLUME_MIN: return s.volMin;
      case SYMBOL_VOLUME_MAX: return s.volMax;
      case SYMBOL_VOLUME_STEP: return s.volStep;
      case SYMBOL_VOLUME_LIMIT: return s.volLimit;
      case SYMBOL_TRADE_TICK_VALUE:
      case SYMBOL_TRADE_TICK_VALUE_LOSS:
      case SYMBOL_TRADE_TICK_VALUE_PROFIT: return s.tickValue;
     }
   return 0.0;
  }
inline bool SymbolInfoTick(const string &symbol, MqlTick &t)
  {
   if(symbol.s != g_fake.sym.name) return false;
   t = MqlTick();
   t.time = g_fake.time;
   t.bid = g_fake.sym.bid;
   t.ask = g_fake.sym.ask;
   return true;
  }
// Profit in account currency through the tick value, as MT5 computes it for a USD-quoted symbol.
inline bool OrderCalcProfit(ENUM_ORDER_TYPE type, const string &symbol, double lots, double open, double close, double &profit)
  {
   const FakeSym &s = g_fake.sym;
   if(symbol.s != s.name) return false;
   double dir = (type == ORDER_TYPE_BUY) ? 1.0 : -1.0;
   profit = (close - open) * dir / s.tickSize * s.tickValue * lots;
   return true;
  }
inline bool OrderCalcMargin(ENUM_ORDER_TYPE, const string &symbol, double lots, double price, double &margin)
  {
   if(symbol.s != g_fake.sym.name) return false;
   margin = lots * g_fake.sym.contract * price / 100.0 * (g_fake.sym.tickValue / (g_fake.sym.tickSize * g_fake.sym.contract));
   return true;
  }

//--- positions, orders, history --------------------------------------------
inline double FakeProfit(const FakePos &p)
  {
   const FakeSym &s = g_fake.sym;
   double close = (p.type == POSITION_TYPE_BUY) ? s.bid : s.ask;
   double dir = (p.type == POSITION_TYPE_BUY) ? 1.0 : -1.0;
   return (close - p.open) * dir / s.tickSize * s.tickValue * p.volume;
  }
inline int PositionsTotal() { return (int)g_fake.pos.size(); }
inline ulong PositionGetTicket(int i)
  {
   if(i < 0 || i >= (int)g_fake.pos.size()) { g_fake.selPos = -1; return 0; }
   g_fake.selPos = i;
   return g_fake.pos[i].ticket;
  }
inline string PositionGetString(int prop) { return (g_fake.selPos < 0 || prop != POSITION_SYMBOL) ? string() : string(g_fake.pos[g_fake.selPos].symbol); }
inline int64_t PositionGetInteger(int prop)
  {
   if(g_fake.selPos < 0) return 0;
   const FakePos &p = g_fake.pos[g_fake.selPos];
   return (prop == POSITION_TYPE) ? p.type : (prop == POSITION_TIME_MSC ? p.timeMsc : 0);
  }
inline double PositionGetDouble(int prop)
  {
   if(g_fake.selPos < 0) return 0.0;
   const FakePos &p = g_fake.pos[g_fake.selPos];
   switch(prop)
     {
      case POSITION_VOLUME: return p.volume;
      case POSITION_PRICE_OPEN: return p.open;
      case POSITION_SL: return p.sl;
      case POSITION_TP: return p.tp;
      case POSITION_PROFIT: return FakeProfit(p);
      case POSITION_SWAP: return p.swap;
     }
   return 0.0;
  }
inline int OrdersTotal() { return (int)g_fake.ords.size(); }
inline ulong OrderGetTicket(int i)
  {
   if(i < 0 || i >= (int)g_fake.ords.size()) { g_fake.selOrd = -1; return 0; }
   g_fake.selOrd = i;
   return g_fake.ords[i].ticket;
  }
inline string OrderGetString(int prop) { return (g_fake.selOrd < 0 || prop != ORDER_SYMBOL) ? string() : string(g_fake.ords[g_fake.selOrd].symbol); }
inline int64_t OrderGetInteger(int prop)
  {
   if(g_fake.selOrd < 0) return 0;
   const FakeOrd &o = g_fake.ords[g_fake.selOrd];
   if(prop == ORDER_TYPE) return o.type;
   if(prop == ORDER_TYPE_TIME) return o.typeTime;
   if(prop == ORDER_TIME_EXPIRATION) return o.expiration;
   return 0;
  }
inline double OrderGetDouble(int prop)
  {
   if(g_fake.selOrd < 0) return 0.0;
   const FakeOrd &o = g_fake.ords[g_fake.selOrd];
   switch(prop)
     {
      case ORDER_VOLUME_CURRENT: return o.volume;
      case ORDER_PRICE_OPEN: return o.price;
      case ORDER_SL: return o.sl;
      case ORDER_TP: return o.tp;
      case ORDER_PRICE_STOPLIMIT: return o.stoplimit;
     }
   return 0.0;
  }
inline bool HistorySelect(datetime, datetime) { return true; }
inline int HistoryDealsTotal() { return 0; }
inline ulong HistoryDealGetTicket(int) { return 0; }
inline int64_t HistoryDealGetInteger(ulong, int) { return 0; }
inline double HistoryDealGetDouble(ulong, int) { return 0.0; }
inline string HistoryDealGetString(ulong, int) { return string(); }
inline double HistoryOrderGetDouble(ulong, int) { return 0.0; }

// The fake server: applies the request to the fake trades (unless forceRetcode says otherwise).
inline uint FakeApply(const MqlTradeRequest &req, MqlTradeResult &res)
  {
   if(req.action == TRADE_ACTION_SLTP)
     {
      for(auto &p : g_fake.pos)
         if(p.ticket == req.position)
           {
            if(p.sl == req.sl && p.tp == req.tp) return TRADE_RETCODE_NO_CHANGES;
            p.sl = req.sl;
            p.tp = req.tp;
            return TRADE_RETCODE_DONE;
           }
      return TRADE_RETCODE_INVALID;
     }
   if(req.action == TRADE_ACTION_MODIFY)
     {
      for(auto &o : g_fake.ords)
         if(o.ticket == req.order)
           {
            if(o.price == req.price && o.sl == req.sl && o.tp == req.tp) return TRADE_RETCODE_NO_CHANGES;
            o.price = req.price;
            o.sl = req.sl;
            o.tp = req.tp;
            o.stoplimit = req.stoplimit;
            o.typeTime = req.type_time;
            o.expiration = req.expiration;
            return TRADE_RETCODE_DONE;
           }
      return TRADE_RETCODE_INVALID;
     }
   if(req.action == TRADE_ACTION_DEAL)
     {
      FakePos p{g_fake.nextTicket++, req.type == ORDER_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, req.volume, req.price, req.sl, req.tp,
                0.0, (int64_t)g_fake.time * 1000, req.symbol.s};
      g_fake.pos.push_back(p);
      res.order = res.deal = p.ticket;
      res.price = req.price;
      res.volume = req.volume;
      return TRADE_RETCODE_DONE;
     }
   if(req.action == TRADE_ACTION_PENDING)
     {
      FakeOrd o{g_fake.nextTicket++, (int)req.type, req.volume, req.price, req.sl, req.tp, req.stoplimit, (int)req.type_time, req.expiration,
                req.symbol.s};
      g_fake.ords.push_back(o);
      res.order = o.ticket;
      res.price = req.price;
      res.volume = req.volume;
      return TRADE_RETCODE_PLACED;
     }
   return TRADE_RETCODE_INVALID;
  }
inline bool OrderSend(const MqlTradeRequest &req, MqlTradeResult &res)
  {
   g_fake.requests.push_back(req);
   if(g_fake.onSend)
      g_fake.onSend(req);
   res = MqlTradeResult();
   uint code = g_fake.forceRetcode ? g_fake.forceRetcode : FakeApply(req, res);
   res.retcode = code;
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_DONE_PARTIAL;
  }

//--- chart and objects -----------------------------------------------------
inline int64_t ChartID() { return 1; }
inline void ChartRedraw(int64_t = 0) {}
inline int64_t ChartGetInteger(int64_t, int prop, int = 0)
  {
   if(prop == CHART_WIDTH_IN_PIXELS) return g_fake.chartW;
   if(prop == CHART_HEIGHT_IN_PIXELS) return g_fake.chartH;
   if(prop == CHART_COLOR_BACKGROUND) return g_fake.chartBg;
   auto it = g_fake.chartI.find(prop);
   return it == g_fake.chartI.end() ? 0 : it->second;
  }
inline bool ChartSetInteger(int64_t, int prop, int64_t v) { g_fake.chartI[prop] = v; return true; }
inline double ChartGetDouble(int64_t, int prop, int = 0) { auto it = g_fake.chartD.find(prop); return it == g_fake.chartD.end() ? 0.0 : it->second; }
inline bool ChartSetDouble(int64_t, int prop, double v) { g_fake.chartD[prop] = v; return true; }
inline bool ChartSaveTemplate(int64_t, const string &name)
  {
   g_fake.templates.push_back(name.s);
   g_fake.levelsAtSave = g_fake.chartI[CHART_SHOW_TRADE_LEVELS];
   return true;
  }
inline bool ChartTimePriceToXY(int64_t, int, datetime, double price, int &x, int &y)
  {
   double top = 0.0, bottom = 0.0;
   FakeRange(top, bottom);
   x = g_fake.chartW - 300;
   y = (int)std::lround((top - price) / (top - bottom) * g_fake.chartH);
   return true;
  }
inline FakeObj *FakeFind(const string &name) { auto it = g_fake.objs.find(name.s); return it == g_fake.objs.end() ? nullptr : &it->second; }
inline bool ObjectCreate(int64_t, const string &name, int type, int, datetime t1, double p1, datetime t2 = 0, double p2 = 0.0)
  {
   if(FakeFind(name)) { g_fake.lastError = 4200; return false; }
   FakeObj o;
   o.type = type;
   o.order = ++g_fake.objSeq;
   o.i[OBJPROP_TIME * 16] = t1;
   o.d[OBJPROP_PRICE * 16] = p1;
   o.i[OBJPROP_TIME * 16 + 1] = t2;
   o.d[OBJPROP_PRICE * 16 + 1] = p2;
   o.i[OBJPROP_TIMEFRAMES * 16] = OBJ_ALL_PERIODS;
   g_fake.objs[name.s] = o;
   return true;
  }
inline int ObjectFind(int64_t, const string &name) { return FakeFind(name) ? 0 : -1; }
inline bool ObjectDelete(int64_t, const string &name) { return g_fake.objs.erase(name.s) > 0; }
inline int ObjectsDeleteAll(int64_t, const string &prefix, int = -1, int = -1)
  {
   int n = 0;
   for(auto it = g_fake.objs.begin(); it != g_fake.objs.end();)
      if(it->first.compare(0, prefix.s.size(), prefix.s) == 0) { it = g_fake.objs.erase(it); n++; }
      else ++it;
   return n;
  }
inline bool ObjectSetInteger(int64_t, const string &name, int prop, int64_t v) { FakeObj *o = FakeFind(name); if(!o) return false; o->i[prop * 16] = v; return true; }
inline bool ObjectSetInteger(int64_t, const string &name, int prop, int mod, int64_t v) { FakeObj *o = FakeFind(name); if(!o) return false; o->i[prop * 16 + mod] = v; return true; }
inline bool ObjectSetDouble(int64_t, const string &name, int prop, double v) { FakeObj *o = FakeFind(name); if(!o) return false; o->d[prop * 16] = v; return true; }
inline bool ObjectSetDouble(int64_t, const string &name, int prop, int mod, double v) { FakeObj *o = FakeFind(name); if(!o) return false; o->d[prop * 16 + mod] = v; return true; }
inline bool ObjectSetString(int64_t, const string &name, int prop, const string &v) { FakeObj *o = FakeFind(name); if(!o) return false; o->s[prop] = v.s; return true; }
inline int64_t ObjectGetInteger(int64_t, const string &name, int prop, int mod = 0)
  {
   FakeObj *o = FakeFind(name);
   if(!o) { g_fake.lastError = 4202; return 0; }
   auto it = o->i.find(prop * 16 + mod);
   return it == o->i.end() ? 0 : it->second;
  }
inline double ObjectGetDouble(int64_t, const string &name, int prop, int mod = 0)
  {
   FakeObj *o = FakeFind(name);
   if(!o) { g_fake.lastError = 4202; return 0.0; }
   auto it = o->d.find(prop * 16 + mod);
   return it == o->d.end() ? 0.0 : it->second;
  }
inline string ObjectGetString(int64_t, const string &name, int prop, int = 0)
  {
   FakeObj *o = FakeFind(name);
   if(!o) return string();
   auto it = o->s.find(prop);
   return it == o->s.end() ? string() : string(it->second);
  }
inline bool TextSetFont(const string &, int size, uint = 0, int = 0) { g_fake.fontSize = size; return true; }
inline bool TextGetSize(const string &text, uint &w, uint &h)
  {
   int pts = g_fake.fontSize < 0 ? -g_fake.fontSize / 10 : g_fake.fontSize;
   w = (uint)(text.s.size() * pts * 0.75 + 1);
   h = (uint)(pts * 1.6);
   return true;
  }

//--- files (in memory) -----------------------------------------------------
inline std::string FakeKey(const string &name, int flags) { return ((flags & FILE_COMMON) ? "common:" : "local:") + name.s; }
inline bool FolderCreate(const string &, int = 0) { return true; }
inline bool FileIsExist(const string &name, int flags = 0) { return g_fake.files.count(FakeKey(name, flags)) > 0; }
inline int FileOpen(const string &name, int flags, ...)
  {
   std::string key = FakeKey(name, flags);
   bool exists = g_fake.files.count(key) > 0;
   if(!(flags & FILE_WRITE) && !exists) { g_fake.lastError = 5004; return INVALID_HANDLE; }
   if((flags & FILE_WRITE) && !(flags & FILE_READ)) g_fake.files[key] = "";
   else if(!exists) g_fake.files[key] = "";
   FakeFile f;
   f.key = key;
   f.data = g_fake.files[key];
   int h = g_fake.nextHandle++;
   g_fake.handles[h] = f;
   return h;
  }
inline void FileClose(int h)
  {
   auto it = g_fake.handles.find(h);
   if(it == g_fake.handles.end()) return;
   g_fake.files[it->second.key] = it->second.data;
   g_fake.handles.erase(it);
  }
inline bool FileIsEnding(int h) { auto &f = g_fake.handles[h]; return f.pos >= f.data.size(); }
inline string FileReadString(int h, int = -1)
  {
   auto &f = g_fake.handles[h];
   size_t end = f.data.find('\n', f.pos);
   if(end == std::string::npos) end = f.data.size();
   std::string line = f.data.substr(f.pos, end - f.pos);
   if(!line.empty() && line.back() == '\r') line.pop_back();
   f.pos = (end < f.data.size()) ? end + 1 : end;
   return string(line);
  }
inline uint FileWriteString(int h, const string &text, int = -1)
  {
   auto &f = g_fake.handles[h];
   f.data.replace(f.pos, std::min(text.s.size(), f.data.size() - std::min(f.pos, f.data.size())), text.s);
   f.pos += text.s.size();
   return (uint)text.s.size();
  }
inline uint64_t FileSize(int h) { return g_fake.handles[h].data.size(); }
inline bool FileSeek(int h, int64_t offset, int origin)
  {
   auto &f = g_fake.handles[h];
   f.pos = (origin == SEEK_END) ? f.data.size() + offset : (size_t)offset;
   return true;
  }
inline bool FileMove(const string &src, int f1, const string &dst, int f2)
  {
   std::string a = FakeKey(src, f1);
   if(!g_fake.files.count(a)) return false;
   g_fake.files[FakeKey(dst, f2)] = g_fake.files[a];
   g_fake.files.erase(a);
   return true;
  }
inline bool FileDelete(const string &name, int flags = 0) { return g_fake.files.erase(FakeKey(name, flags)) > 0; }

// MQL5 stops a program on a floating-point zero divide; so does this build (Windows and glibc).
inline void MqlTrapZeroDivide()
  {
#if defined(_WIN32)
   _controlfp(_MCW_EM & ~_EM_ZERODIVIDE, _MCW_EM);
#elif defined(__GLIBC__)
   feenableexcept(FE_DIVBYZERO);
#endif
  }

// MQL5's long is 64 bits on every platform; Windows C++'s is 32. Defined last, after every header.
#define long int64_t
