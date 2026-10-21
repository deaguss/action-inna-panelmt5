//+------------------------------------------------------------------+
//| ActionInna - math, parsing, formatting and logging helpers       |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_UTIL_MQH
#define ACTIONINNA_UTIL_MQH

#include "Defines.mqh"

bool g_aiDebugLog = false;

// A zero divide stops an EA without OnDeinit, which would leave the One-Click panel hidden,
// so every division goes through here.
double AiSafeDiv(const double a, const double b, const double fallback = 0.0)
  {
   if(b == 0.0 || !MathIsValidNumber(a) || !MathIsValidNumber(b))
      return fallback;
   double r = a / b;
   return MathIsValidNumber(r) ? r : fallback;
  }

// Decimals needed to write a step: 0.01 -> 2, 0.25 -> 2, 1 -> 0.
int AiStepDigits(const double step)
  {
   if(step <= 0.0)
      return 2;
   for(int d = 0; d <= 8; d++)
     {
      double scaled = step * MathPow(10.0, d);
      if(MathAbs(scaled - MathRound(scaled)) < 1e-7)
         return d;
     }
   return 8;
  }

// Rounds down to a multiple of step. The small epsilon keeps 0.39999999 from becoming 0.39.
double AiFloorToStep(const double value, const double step)
  {
   if(step <= 0.0)
      return value;
   double n = MathFloor(value / step + 1e-7);
   return NormalizeDouble(n * step, AiStepDigits(step));
  }

// Accepts "1.5", "1,5", " 25 ", "2%", "$100". Anything else returns false.
bool AiParseNumber(const string text, double &value)
  {
   string s = text;
   StringTrimLeft(s);
   StringTrimRight(s);
   StringReplace(s, " ", "");
   StringReplace(s, "%", "");
   StringReplace(s, "$", "");
   StringReplace(s, ",", ".");
   int len = StringLen(s);
   if(len == 0)
      return false;
   int dots = 0;
   int digits = 0;
   for(int i = 0; i < len; i++)
     {
      ushort c = StringGetCharacter(s, i);
      if(c >= '0' && c <= '9')
         digits++;
      else if(c == '.')
         dots++;
      else if(!(c == '-' && i == 0))
         return false;
     }
   if(digits == 0 || dots > 1)
      return false;
   value = StringToDouble(s);
   return MathIsValidNumber(value);
  }

// "1.50" -> "1.5", "2.00" -> "2".
string AiTrimZeros(const string s)
  {
   if(StringFind(s, ".") < 0)
      return s;
   string r = s;
   int len = StringLen(r);
   while(len > 0 && StringGetCharacter(r, len - 1) == '0')
     {
      r = StringSubstr(r, 0, len - 1);
      len--;
     }
   if(len > 0 && StringGetCharacter(r, len - 1) == '.')
      r = StringSubstr(r, 0, len - 1);
   return r;
  }

// 12345.6 -> "12,345.60" (value must be >= 0).
string AiGroup(const double v, const int decimals)
  {
   string s = DoubleToString(MathAbs(v), decimals);
   int dot = StringFind(s, ".");
   string ip = (dot < 0) ? s : StringSubstr(s, 0, dot);
   string fp = (dot < 0) ? "" : StringSubstr(s, dot);
   string out = "";
   int n = StringLen(ip);
   for(int i = 0; i < n; i++)
     {
      out += StringSubstr(ip, i, 1);
      int left = n - 1 - i;
      if(left > 0 && left % 3 == 0)
         out += ",";
     }
   return out + fp;
  }

// "$1,234.50" for USD accounts, "1,234.50 EUR" or "1,234.50 USC" for others.
string AiMoney(const double v, const string currency, const bool withSign = false, const int decimals = 2)
  {
   string num = AiGroup(MathAbs(v), decimals);
   string sign = "";
   if(v < 0.0 && MathAbs(v) >= 0.5 * MathPow(10.0, -decimals))
      sign = "-";
   else if(withSign && v > 0.0)
      sign = "+";
   if(currency == "USD")
      return sign + "$" + num;
   return sign + num + " " + currency;
  }

ulong AiNowMs()
  {
   return GetMicrosecondCount() / 1000;
  }

string AiOrderTypeName(const ENUM_ORDER_TYPE t)
  {
   switch(t)
     {
      case ORDER_TYPE_BUY:
         return "BUY";
      case ORDER_TYPE_SELL:
         return "SELL";
      case ORDER_TYPE_BUY_LIMIT:
         return "BUY LIMIT";
      case ORDER_TYPE_SELL_LIMIT:
         return "SELL LIMIT";
      case ORDER_TYPE_BUY_STOP:
         return "BUY STOP";
      case ORDER_TYPE_SELL_STOP:
         return "SELL STOP";
      default:
         return "ORDER";
     }
  }

// Prints to the Experts tab and, when enabled, appends to MQL5\Files\ActionInna\log.txt. Every
// chart with the panel writes to the same file, often in the same second after MT5 starts, so the
// file is opened shared for writing too; without that, all but the first chart lost their lines.
void AiLog(const string msg)
  {
   Print(AI_NAME, ": ", msg);
   if(!g_aiDebugLog)
      return;
   string path = AI_FILES_DIR + "\\log.txt";
   int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
   int h = INVALID_HANDLE;
   for(int attempt = 0; attempt < 3 && h == INVALID_HANDLE; attempt++)
     {
      h = FileOpen(path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | share);
      if(h == INVALID_HANDLE)
         Sleep(15);
     }
   if(h == INVALID_HANDLE)
      return;
   if(FileSize(h) > 512 * 1024)
     {
      FileClose(h);
      h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI | share);
      if(h == INVALID_HANDLE)
         return;
     }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + "  " + _Symbol + "  " + msg + "\r\n");
   FileClose(h);
  }

#endif
