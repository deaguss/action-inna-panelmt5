//+------------------------------------------------------------------+
//| ActionInna - TradingView tickers to the broker's symbols         |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_SYMBOLMAP_MQH
#define ACTIONINNA_SYMBOLMAP_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "Memory.mqh"

#define AI_SYMBOLS_FILE  "ActionInna\\symbols.txt"

// One broker symbol that may be the ticker's market. Lower rank is a closer match:
// 0 the same name, 1 the same letters (#XAUUSD), 2 a prefix or suffix (XAUUSDm, XAUUSD.r),
// 3 another name for the same market (GOLD), 4 the same base and profit currencies.
struct AiSymCand
  {
   string            name;
   string            description;
   bool              visible;
   int               rank;
  };

// "OANDA:XAUUSD" -> "XAUUSD".
string AiTvTicker(const string ticker)
  {
   string t = ticker;
   int colon = StringFind(t, ":");
   while(colon >= 0)
     {
      t = StringSubstr(t, colon + 1);
      colon = StringFind(t, ":");
     }
   StringTrimLeft(t);
   StringTrimRight(t);
   StringToUpper(t);
   return t;
  }

// Letters and digits only, in upper case: "#xauusd.r" -> "XAUUSDR".
string AiSymNorm(const string s)
  {
   string up = s;
   StringToUpper(up);
   string out = "";
   int n = StringLen(up);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(up, i);
      if((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
         out += ShortToString(c);
     }
   return out;
  }

// Other names brokers use for the same market, one family per line.
string AiSymFamily(const string norm)
  {
   string families[] =
     {
      "XAUUSD GOLD",
      "XAGUSD SILVER",
      "US30 DJ30 WS30 DJI DOW US30USD USA30 DJIA",
      "NAS100 USTEC US100 NDX NQ100 USATEC NASDAQ100",
      "SPX500 US500 SPX SP500 USA500 SPXUSD",
      "GER40 DE40 DAX40 GER30 DE30 DAX",
      "UK100 FTSE100 UKX FTSE",
      "JP225 JPN225 NIKKEI225 NI225 NIKKEI",
      "USOIL WTI XTIUSD USCRUDE CRUDEOIL",
      "UKOIL BRENT XBRUSD"
     };
   int n = ArraySize(families);
   for(int i = 0; i < n; i++)
      if(StringFind(" " + families[i] + " ", " " + norm + " ") >= 0)
         return families[i];
   return "";
  }

// A short broker suffix or prefix: up to 4 letters or digits, like m, c, pro, r, ecn.
bool AiShortAffix(const int len)
  {
   return len > 0 && len <= 4;
  }

// How close 'name' comes to the ticker, or -1 when it does not match.
int AiSymRank(const string name, const string ticker, const string tickerNorm, const string family)
  {
   string up = name;
   StringToUpper(up);
   if(up == ticker)
      return 0;
   string norm = AiSymNorm(name);
   if(norm == tickerNorm)
      return 1;
   int nl = StringLen(norm);
   int tl = StringLen(tickerNorm);
   if(tl >= 3 && nl > tl)
     {
      if(StringFind(norm, tickerNorm) == 0 && AiShortAffix(nl - tl))
         return 2;
      if(StringFind(norm, tickerNorm) == nl - tl && AiShortAffix(nl - tl))
         return 2;
     }
   if(family != "")
     {
      string members[];
      int m = StringSplit(family, ' ', members);
      for(int i = 0; i < m; i++)
        {
         string other = members[i];
         int ol = StringLen(other);
         if(other == tickerNorm || ol < 3)
            continue;
         if(norm == other || (nl > ol && StringFind(norm, other) == 0 && AiShortAffix(nl - ol)) ||
            (nl > ol && StringFind(norm, other) == nl - ol && AiShortAffix(nl - ol)))
            return 3;
        }
     }
   return -1;
  }

// The broker's symbols that may be the ticker's market, closest first, Market Watch symbols first
// among equals. At most maxOut.
int AiSymbolCandidates(const string tickerIn, AiSymCand &out[], const int maxOut = 10)
  {
   ArrayResize(out, 0);
   string ticker = AiTvTicker(tickerIn);
   string tickerNorm = AiSymNorm(ticker);
   if(tickerNorm == "")
      return 0;
   string family = AiSymFamily(tickerNorm);
   bool pair = (StringLen(tickerNorm) == 6);
   string base = pair ? StringSubstr(tickerNorm, 0, 3) : "";
   string profit = pair ? StringSubstr(tickerNorm, 3, 3) : "";
   AiSymCand all[];
   int n = 0;
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      if(name == "")
         continue;
      int rank = AiSymRank(name, ticker, tickerNorm, family);
      if(rank < 0 && pair)
        {
         string b = SymbolInfoString(name, SYMBOL_CURRENCY_BASE);
         string p = SymbolInfoString(name, SYMBOL_CURRENCY_PROFIT);
         StringToUpper(b);
         StringToUpper(p);
         if(b == base && p == profit)
            rank = 4;
        }
      if(rank < 0)
         continue;
      ArrayResize(all, n + 1, 16);
      all[n].name = name;
      all[n].description = SymbolInfoString(name, SYMBOL_DESCRIPTION);
      all[n].visible = (SymbolInfoInteger(name, SYMBOL_VISIBLE) != 0);
      all[n].rank = rank;
      n++;
     }
   // Insertion sort: rank, then Market Watch first, then the shorter name, then by name.
   for(int i = 1; i < n; i++)
     {
      AiSymCand c = all[i];
      int j = i - 1;
      while(j >= 0)
        {
         bool after = (all[j].rank > c.rank) ||
                      (all[j].rank == c.rank && !all[j].visible && c.visible) ||
                      (all[j].rank == c.rank && all[j].visible == c.visible && StringLen(all[j].name) > StringLen(c.name)) ||
                      (all[j].rank == c.rank && all[j].visible == c.visible && StringLen(all[j].name) == StringLen(c.name) && all[j].name > c.name);
         if(!after)
            break;
         all[j + 1] = all[j];
         j--;
        }
      all[j + 1] = c;
     }
   int keep = MathMin(n, maxOut);
   ArrayResize(out, keep);
   for(int i = 0; i < keep; i++)
      out[i] = all[i];
   return keep;
  }

// The trader's choice of symbol per server and ticker, in Common\Files\ActionInna\symbols.txt.
class CAiSymbolMap
  {
private:
   CAiKv             m_kv;

   string            Key(const string server, const string ticker) const
     {
      return "map|" + server + "|" + AiSymNorm(AiTvTicker(ticker));
     }

public:
   // The remembered choice when it is still a symbol of this broker; otherwise the best candidate
   // when it is clear (the only one at its rank); otherwise "".
   string            Pick(const string server, const string ticker, const AiSymCand &cands[])
     {
      m_kv.Load(AI_SYMBOLS_FILE);
      string key = Key(server, ticker);
      int n = ArraySize(cands);
      string chosen = m_kv.GetS(key, "");
      if(chosen != "" && SymbolInfoDouble(chosen, SYMBOL_POINT) > 0.0)
         return chosen;
      if(n == 0)
         return "";
      if(n == 1 || cands[1].rank > cands[0].rank)
         return cands[0].name;
      return "";
     }

   bool              Remember(const string server, const string ticker, const string symbol)
     {
      m_kv.Load(AI_SYMBOLS_FILE);
      m_kv.Set(Key(server, ticker), symbol);
      return m_kv.Save(AI_SYMBOLS_FILE);
     }
  };

#endif
