//+------------------------------------------------------------------+
//| ActionInna - recall of earlier SL/TP and the settings file       |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_MEMORY_MQH
#define ACTIONINNA_MEMORY_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "SymbolSpec.mqh"

// Files live in Terminal\Common\Files\ActionInna, shared by every MT5 terminal on this PC:
//   recall\<SYMBOL>.txt   newest first, one "key=value;..." line per remembered SL/TP
//   settings.txt          panel state (risk chip, custom values, toggles, position)

string AiSafeFileName(const string s)
  {
   string r = s;
   string bad = "\\/:*?\"<>| ";
   int n = StringLen(bad);
   for(int i = 0; i < n; i++)
      StringReplace(r, StringSubstr(bad, i, 1), "_");
   return r;
  }

string AiMemToLine(const AiMem &m)
  {
   return "t=" + IntegerToString(m.t) +
          ";side=" + IntegerToString(m.side) +
          ";slm=" + IntegerToString(m.slMode) +
          ";sld=" + DoubleToString(m.slDist, 8) +
          ";slx=" + DoubleToString(m.slPrice, 8) +
          ";tpm=" + IntegerToString(m.tpMode) +
          ";tpd=" + DoubleToString(m.tpDist, 8) +
          ";tpx=" + DoubleToString(m.tpPrice, 8) +
          ";tpr=" + DoubleToString(m.tpR, 2);
  }

// False for lines that are damaged or remember nothing usable.
bool AiMemFromLine(const string line, AiMem &m)
  {
   ZeroMemory(m);
   string parts[];
   int n = StringSplit(line, ';', parts);
   if(n < 3)
      return false;
   int seen = 0;
   for(int i = 0; i < n; i++)
     {
      int eq = StringFind(parts[i], "=");
      if(eq <= 0)
         continue;
      string k = StringSubstr(parts[i], 0, eq);
      string v = StringSubstr(parts[i], eq + 1);
      if(k == "t")
        {
         m.t = StringToInteger(v);
         seen++;
        }
      else if(k == "side")
         m.side = (int)StringToInteger(v);
      else if(k == "slm")
         m.slMode = (int)StringToInteger(v);
      else if(k == "sld")
        {
         m.slDist = StringToDouble(v);
         seen++;
        }
      else if(k == "slx")
         m.slPrice = StringToDouble(v);
      else if(k == "tpm")
         m.tpMode = (int)StringToInteger(v);
      else if(k == "tpd")
         m.tpDist = StringToDouble(v);
      else if(k == "tpx")
         m.tpPrice = StringToDouble(v);
      else if(k == "tpr")
         m.tpR = StringToDouble(v);
     }
   if(seen < 2)
      return false;
   if(!MathIsValidNumber(m.slDist) || !MathIsValidNumber(m.tpDist) || !MathIsValidNumber(m.tpR))
      return false;
   if(m.slDist < 0.0 || m.tpDist < 0.0 || m.tpR < 0.0)
      return false;
   if(m.slMode != AI_LEVEL_PIPS && m.slMode != AI_LEVEL_PRICE)
      m.slMode = AI_LEVEL_PIPS;
   if(m.tpMode != AI_LEVEL_PIPS && m.tpMode != AI_LEVEL_PRICE && m.tpMode != AI_LEVEL_RR)
      m.tpMode = AI_LEVEL_PIPS;
   return (m.slDist > 0.0 || m.tpDist > 0.0);
  }

// Two distances read back from the file are equal when they differ by less than float noise
// relative to their size (a gold stop of 5.0 and a EURUSD stop of 0.0025 both compare cleanly).
bool AiDistSame(const double a, const double b)
  {
   return MathAbs(a - b) <= 1e-9 + 1e-7 * MathMax(MathAbs(a), MathAbs(b));
  }

// Same choice of SL and TP: price levels compare by price, distances by distance, R by R.
bool AiMemSame(const AiMem &a, const AiMem &b)
  {
   if(a.slMode != b.slMode || a.tpMode != b.tpMode)
      return false;
   bool slSame = (a.slMode == AI_LEVEL_PRICE) ? AiDistSame(a.slPrice, b.slPrice) : AiDistSame(a.slDist, b.slDist);
   bool tpSame = false;
   if(a.tpMode == AI_LEVEL_PRICE)
      tpSame = AiDistSame(a.tpPrice, b.tpPrice);
   else if(a.tpMode == AI_LEVEL_RR)
      tpSame = (MathAbs(a.tpR - b.tpR) < 0.005);
   else
      tpSame = AiDistSame(a.tpDist, b.tpDist);
   return slSame && tpSame;
  }

void AiMemRemoveAt(AiMem &arr[], const int idx)
  {
   int n = ArraySize(arr);
   if(idx < 0 || idx >= n)
      return;
   for(int i = idx; i < n - 1; i++)
      arr[i] = arr[i + 1];
   ArrayResize(arr, n - 1);
  }

// Puts m first, drops an older equal record, keeps at most AI_MEM_MAX.
void AiMemPush(AiMem &arr[], const AiMem &m)
  {
   for(int i = ArraySize(arr) - 1; i >= 0; i--)
      if(AiMemSame(arr[i], m))
         AiMemRemoveAt(arr, i);
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   for(int j = n; j > 0; j--)
      arr[j] = arr[j - 1];
   arr[0] = m;
   if(ArraySize(arr) > AI_MEM_MAX)
      ArrayResize(arr, AI_MEM_MAX);
  }

string AiMemPath(const string symbol)
  {
   return AI_FILES_DIR + "\\recall\\" + AiSafeFileName(symbol) + ".txt";
  }

int AiMemLoad(const string symbol, AiMem &arr[])
  {
   ArrayResize(arr, 0);
   string path = AiMemPath(symbol);
   if(!FileIsExist(path, FILE_COMMON))
      return 0;
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return 0;
   while(!FileIsEnding(h) && ArraySize(arr) < AI_MEM_MAX)
     {
      string line = FileReadString(h);
      AiMem m;
      if(AiMemFromLine(line, m))
        {
         int n = ArraySize(arr);
         ArrayResize(arr, n + 1);
         arr[n] = m;
        }
     }
   FileClose(h);
   return ArraySize(arr);
  }

// Written to a temporary file first, then moved over the old one, so a chart reading at the
// same moment never sees half a file.
bool AiMemSave(const string symbol, const AiMem &arr[])
  {
   string path = AiMemPath(symbol);
   string tmp = path + "." + IntegerToString(ChartID()) + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
      FileWriteString(h, AiMemToLine(arr[i]) + "\r\n");
   FileClose(h);
   if(!FileMove(tmp, FILE_COMMON, path, FILE_COMMON | FILE_REWRITE))
     {
      FileDelete(tmp, FILE_COMMON);
      return false;
     }
   return true;
  }

// A record from a real order: only a stop on the loss side and a target on the profit side
// count (a stop already moved to break-even is not a stop distance).
bool AiMemFill(AiMem &m, const int side, const double open, const double sl, const double tp, const long t)
  {
   ZeroMemory(m);
   if(open <= 0.0)
      return false;
   m.t = t;
   m.side = side;
   m.slMode = AI_LEVEL_PIPS;
   m.tpMode = AI_LEVEL_PIPS;
   if(sl > 0.0 && (side == AI_BUY ? sl < open : sl > open))
     {
      m.slDist = MathAbs(open - sl);
      m.slPrice = sl;
     }
   if(tp > 0.0 && (side == AI_BUY ? tp > open : tp < open))
     {
      m.tpDist = MathAbs(tp - open);
      m.tpPrice = tp;
     }
   if(m.slDist > 0.0 && m.tpDist > 0.0)
      m.tpR = m.tpDist / m.slDist;
   return (m.slDist > 0.0 || m.tpDist > 0.0);
  }

// When nothing was saved yet: the newest SL/TP used on this symbol, from the open positions
// first, then from the fills of the last 90 days.
bool AiMemFromHistory(const string symbol, AiMem &m)
  {
   ZeroMemory(m);
   long best = 0;
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      long tm = PositionGetInteger(POSITION_TIME_MSC);
      if(tm <= best)
         continue;
      int side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? AI_BUY : AI_SELL;
      AiMem cand;
      if(AiMemFill(cand, side, PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP), tm / 1000))
        {
         m = cand;
         best = tm;
         found = true;
        }
     }
   if(found)
      return true;
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 90 * 86400, now + 86400))
      return false;
   for(int j = HistoryDealsTotal() - 1; j >= 0; j--)
     {
      ulong deal = HistoryDealGetTicket(j);
      if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != symbol)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      long dt = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL)
         continue;
      ulong order = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);
      if(order == 0)
         continue;
      double sl = HistoryOrderGetDouble(order, ORDER_SL);
      double tp = HistoryOrderGetDouble(order, ORDER_TP);
      int side = (dt == DEAL_TYPE_BUY) ? AI_BUY : AI_SELL;
      if(AiMemFill(m, side, HistoryDealGetDouble(deal, DEAL_PRICE), sl, tp, HistoryDealGetInteger(deal, DEAL_TIME)))
         return true;
     }
   return false;
  }

// The record an order that went through leaves for recall: its SL and TP as distances and prices,
// in the modes the trader used. False when the order had neither.
bool AiMemFromPlan(const AiPlan &p, const int side, const int slMode, const int tpMode, const double tpValue, const long t, AiMem &m)
  {
   ZeroMemory(m);
   if(p.entry <= 0.0)
      return false;
   m.t = t;
   m.side = side;
   m.slMode = slMode;
   m.tpMode = tpMode;
   if(p.sl > 0.0)
     {
      m.slPrice = p.sl;
      m.slDist = MathAbs(p.entry - p.sl);
     }
   if(p.tp > 0.0)
     {
      m.tpPrice = p.tp;
      m.tpDist = MathAbs(p.tp - p.entry);
     }
   m.tpR = (tpMode == AI_LEVEL_RR) ? tpValue : p.rr;
   return (m.slDist > 0.0 || m.tpDist > 0.0);
  }

// A remembered price level is reused only if it still sits on the right side of the entry.
bool AiLevelFits(const AiSpec &s, const int side, const double price, const bool isStop, const double entry)
  {
   if(price <= 0.0 || entry <= 0.0)
      return false;
   double d = (price - entry) * side;
   if(isStop)
      d = -d;
   double minDist = MathMax((double)s.stopsLevel, 1.0) * s.point;
   return d >= minDist;
  }

// SL and/or TP from a remembered record, in the mode they were set last time. A price level that no
// longer fits falls back to the same distance. Distances are stored as price, so they convert to this
// symbol's pips whatever the broker. Levels not asked for keep the values passed in. desc says what
// was set ("SL 25 pips, TP 2R"); false when nothing was.
bool AiRecallLevels(const AiSpec &s, const AiMem &m, const int side, const double entry, const bool doSL, const bool doTP,
                    int &slMode, double &slValue, int &tpMode, double &tpValue, string &desc)
  {
   desc = "";
   double pip = (s.pipSize > 0.0) ? s.pipSize : 1.0;
   if(doSL && m.slDist > 0.0)
     {
      if(m.slMode == AI_LEVEL_PRICE && AiLevelFits(s, side, m.slPrice, true, entry))
        {
         slMode = AI_LEVEL_PRICE;
         slValue = m.slPrice;
         desc += "SL " + AiPriceStr(s, slValue);
        }
      else
        {
         slMode = AI_LEVEL_PIPS;
         slValue = NormalizeDouble(m.slDist / pip, 1);
         desc += "SL " + AiTrimZeros(DoubleToString(slValue, 1)) + " pips";
        }
     }
   if(doTP && (m.tpDist > 0.0 || m.tpR > 0.0))
     {
      string part = "";
      if(m.tpMode == AI_LEVEL_PRICE && AiLevelFits(s, side, m.tpPrice, false, entry))
        {
         tpMode = AI_LEVEL_PRICE;
         tpValue = m.tpPrice;
         part = "TP " + AiPriceStr(s, tpValue);
        }
      else if(m.tpMode == AI_LEVEL_RR && m.tpR > 0.0)
        {
         tpMode = AI_LEVEL_RR;
         tpValue = NormalizeDouble(m.tpR, 2);
         part = "TP " + AiTrimZeros(DoubleToString(tpValue, 2)) + "R";
        }
      else if(m.tpDist > 0.0)
        {
         tpMode = AI_LEVEL_PIPS;
         tpValue = NormalizeDouble(m.tpDist / pip, 1);
         part = "TP " + AiTrimZeros(DoubleToString(tpValue, 1)) + " pips";
        }
      if(part != "")
         desc += (desc == "") ? part : ", " + part;
     }
   return (desc != "");
  }

// A tiny key=value store for settings.txt.
class CAiKv
  {
private:
   string            m_k[];
   string            m_v[];

   int               Find(const string k) const
     {
      int n = ArraySize(m_k);
      for(int i = 0; i < n; i++)
         if(m_k[i] == k)
            return i;
      return -1;
     }

public:
   void              Clear()
     {
      ArrayResize(m_k, 0);
      ArrayResize(m_v, 0);
     }

   void              Set(const string k, const string v)
     {
      int i = Find(k);
      if(i < 0)
        {
         i = ArraySize(m_k);
         ArrayResize(m_k, i + 1);
         ArrayResize(m_v, i + 1);
         m_k[i] = k;
        }
      m_v[i] = v;
     }

   bool              Has(const string k) const
     {
      return Find(k) >= 0;
     }

   long              GetI(const string k, const long def) const
     {
      int i = Find(k);
      return (i < 0) ? def : StringToInteger(m_v[i]);
     }

   double            GetD(const string k, const double def) const
     {
      int i = Find(k);
      return (i < 0) ? def : StringToDouble(m_v[i]);
     }

   bool              GetB(const string k, const bool def) const
     {
      int i = Find(k);
      return (i < 0) ? def : (m_v[i] == "1");
     }

   string            GetS(const string k, const string def) const
     {
      int i = Find(k);
      return (i < 0) ? def : m_v[i];
     }

   bool              Load(const string path)
     {
      Clear();
      if(!FileIsExist(path, FILE_COMMON))
         return false;
      int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(h == INVALID_HANDLE)
         return false;
      while(!FileIsEnding(h))
        {
         string line = FileReadString(h);
         int eq = StringFind(line, "=");
         if(eq > 0)
            Set(StringSubstr(line, 0, eq), StringSubstr(line, eq + 1));
        }
      FileClose(h);
      return true;
     }

   bool              Save(const string path) const
     {
      string tmp = path + "." + IntegerToString(ChartID()) + ".tmp";
      int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(h == INVALID_HANDLE)
         return false;
      int n = ArraySize(m_k);
      for(int i = 0; i < n; i++)
         FileWriteString(h, m_k[i] + "=" + m_v[i] + "\r\n");
      FileClose(h);
      if(!FileMove(tmp, FILE_COMMON, path, FILE_COMMON | FILE_REWRITE))
        {
         FileDelete(tmp, FILE_COMMON);
         return false;
        }
      return true;
     }
  };

#endif
