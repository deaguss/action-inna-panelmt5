//+------------------------------------------------------------------+
//| ActionInna - symbol data, pip size and normalisation             |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_SYMBOLSPEC_MQH
#define ACTIONINNA_SYMBOLSPEC_MQH

#include "Defines.mqh"
#include "Util.mqh"

struct AiSpec
  {
   string            symbol;
   bool              ok;
   int               digits;
   double            point;
   double            tickSize;
   double            contractSize;
   double            volMin;
   double            volMax;
   double            volStep;
   double            volLimit;
   int               volDigits;
   double            pipSize;      // price distance of one pip
   double            pipPoints;    // points in one pip
   int               stopsLevel;   // points
   int               tradeMode;
   int               exeMode;
   int               fillingFlags;
   int               orderFlags;
   int               expirationFlags;
  };

// Trader mode counts gold at 0.1 per pip (as gold traders quote it), a 5- or 3-digit symbol at
// 10 points, anything else at one point. Exness counts 10 points on every symbol.
double AiPipSize(const string symbol, const int digits, const double point, const int mode)
  {
   if(point <= 0.0)
      return 0.0;
   if(mode == AI_PIP_POINT)
      return point;
   if(mode == AI_PIP_EXNESS)
      return point * 10.0;
   string up = symbol;
   StringToUpper(up);
   if(StringFind(up, "XAU") == 0 || StringFind(up, "GOLD") >= 0)
      return 0.1;
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
  }

bool AiLoadSpec(const string symbol, const int pipMode, AiSpec &s)
  {
   ZeroMemory(s);
   s.symbol = symbol;
   s.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   s.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   s.tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(s.tickSize <= 0.0)
      s.tickSize = s.point;
   s.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   s.volMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   s.volMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   s.volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   s.volLimit = SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT);
   if(s.volStep <= 0.0)
      s.volStep = (s.volMin > 0.0) ? s.volMin : 0.01;
   s.volDigits = AiStepDigits(s.volStep);
   s.stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   s.tradeMode = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   s.exeMode = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
   s.fillingFlags = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   s.orderFlags = (int)SymbolInfoInteger(symbol, SYMBOL_ORDER_MODE);
   s.expirationFlags = (int)SymbolInfoInteger(symbol, SYMBOL_EXPIRATION_MODE);
   s.pipSize = AiPipSize(symbol, s.digits, s.point, pipMode);
   s.pipPoints = AiSafeDiv(s.pipSize, s.point, 1.0);
   s.ok = (s.point > 0.0 && s.volMin > 0.0 && s.pipSize > 0.0);
   return s.ok;
  }

// Rounds a price to the symbol's tick size (an index can tick in 0.25 while its point is 0.01).
double AiNormPrice(const AiSpec &s, const double price)
  {
   if(price <= 0.0)
      return 0.0;
   double tick = (s.tickSize > 0.0) ? s.tickSize : s.point;
   if(tick <= 0.0)
      return NormalizeDouble(price, s.digits);
   return NormalizeDouble(MathRound(price / tick) * tick, s.digits);
  }

string AiPriceStr(const AiSpec &s, const double price)
  {
   return DoubleToString(price, s.digits);
  }

string AiLotsStr(const AiSpec &s, const double lots)
  {
   return DoubleToString(lots, s.volDigits);
  }

#endif
