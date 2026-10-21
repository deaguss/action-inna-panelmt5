//+------------------------------------------------------------------+
//| ActionInna tests - generated scenarios                           |
//| Each suite draws random inputs from a seed and checks rules that |
//| must hold for every one of them.                                 |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_SCENARIOS_MQH
#define ACTIONINNA_SCENARIOS_MQH

#include "TestKit.mqh"

// Rounding a lot size down never goes above the value, stays within one step of it, and lands on
// a whole number of steps, including values that are float noise away from a step.
void SuiteFloorToStep(const int n)
  {
   string suite = "Rounding down to a volume step";
   int fails = 0;
   double steps[6] = {0.001, 0.01, 0.1, 1.0, 0.25, 0.05};
   for(int i = 0; i < n; i++)
     {
      double step = steps[RndInt(0, 5)];
      double v = RndRange(0.0, 1000.0);
      if(RndChance(4))
         v = MathRound(v / step) * step;
      double r = AiFloorToStep(v, step);
      double k = r / step;
      bool ok = (r >= 0.0) && (r <= v + step * 1e-6) && (v - r < step * (1.0 + 1e-6)) &&
                (MathAbs(k - MathRound(k)) < 1e-6);
      if(!Expect(ok, fails))
         Detail(suite, "value " + D(v) + ", step " + D(step) + " gave " + D(r));
     }
   Row(suite, n, fails);
  }

// The lot size never risks more than the target, is the largest step that does, respects the
// symbol's minimum and maximum, and says why when there is no lot size.
void SuiteLotsForRisk(const int n)
  {
   string suite = "Lot size from risk";
   int fails = 0;
   for(int i = 0; i < n; i++)
     {
      AiSpec s;
      RandomSpec(s);
      double risk = RndChance(20) ? 0.0 : RndRange(0.01, 100000.0);
      double loss = RndChance(20) ? 0.0 : MathPow(10.0, RndRange(-2.0, 5.0));
      double comm = RndChance(3) ? RndRange(0.0, 20.0) : 0.0;
      int code = -1;
      double lots = AiLotsForRisk(risk, loss, comm, s, code);
      double perLot = loss + comm;
      bool ok = false;
      if(risk <= 0.0)
         ok = (code == AI_LOTS_NO_RISK && lots == 0.0);
      else if(perLot <= 0.0)
         ok = (code == AI_LOTS_NO_VALUE && lots == 0.0);
      else if(code == AI_LOTS_BELOW_MIN)
         ok = (lots == 0.0 && s.volMin * perLot > risk * (1.0 - 1e-6));
      else if(code == AI_LOTS_OK || code == AI_LOTS_CAPPED)
        {
         double k = lots / s.volStep;
         bool onStep = (MathAbs(k - MathRound(k)) < 1e-6);
         bool inRange = (lots >= s.volMin - 1e-9 && lots <= s.volMax + 1e-9);
         // The floor's tiny epsilon may round a hair up: allow a millionth of one step.
         bool notAbove = (lots * perLot <= risk + perLot * s.volStep * 1e-6 + 1e-9);
         bool largest = (code == AI_LOTS_CAPPED) || ((lots + s.volStep) * perLot > risk * (1.0 - 1e-9));
         bool capOk = (code != AI_LOTS_CAPPED) || (MathAbs(lots - AiFloorToStep(s.volMax, s.volStep)) < 1e-9);
         ok = onStep && inRange && notAbove && largest && capOk;
        }
      if(!Expect(ok, fails))
         Detail(suite, "risk " + D(risk) + ", loss/lot " + D(loss) + ", commission " + D(comm) + ", min " + D(s.volMin) +
                ", max " + D(s.volMax) + ", step " + D(s.volStep) + " gave " + D(lots) + " (code " + IntegerToString(code) + ")");
     }
   Row(suite, n, fails);
  }

// A normalised price is on the tick grid and within half a tick of the input.
void SuiteNormPrice(const int n)
  {
   string suite = "Prices rounded to the tick size";
   int fails = 0;
   for(int i = 0; i < n; i++)
     {
      AiSpec s;
      RandomSpec(s);
      double p = MathPow(10.0, RndRange(-3.0, 5.0));
      double r = AiNormPrice(s, p);
      double k = r / s.tickSize;
      bool ok = (MathAbs(r - p) <= s.tickSize * 0.5 + 1e-9 * MathMax(1.0, p)) &&
                (MathAbs(k - MathRound(k)) <= 1e-6 + 1e-9 * MathAbs(k));
      if(!Expect(ok, fails))
         Detail(suite, "price " + D(p) + ", tick " + D(s.tickSize) + ", digits " + IntegerToString(s.digits) + " gave " + D(r));
     }
   Row(suite, n, fails);
  }

// Market orders keep their side; a pending order's type follows its entry against the market.
void SuiteResolveType(const int n)
  {
   string suite = "Order type from side and entry";
   int fails = 0;
   for(int i = 0; i < n; i++)
     {
      double bid = RndRange(0.5, 50000.0);
      double ask = bid + (RndChance(5) ? 0.0 : RndRange(0.0, bid * 0.01));
      int side = RndChance(2) ? AI_BUY : AI_SELL;
      bool pending = !RndChance(4);
      double entry = bid * (1.0 + RndRange(-0.05, 0.05));
      int pick = RndInt(0, 5);
      if(pick == 0)
         entry = ask;
      else if(pick == 1)
         entry = bid;
      bool okType = false;
      ENUM_ORDER_TYPE t = AiResolveType(side, pending, entry, bid, ask, okType);
      bool ok = false;
      if(!pending)
         ok = okType && t == ((side == AI_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      else if(side == AI_BUY)
        {
         if(entry < ask)
            ok = okType && t == ORDER_TYPE_BUY_LIMIT;
         else if(entry > ask)
            ok = okType && t == ORDER_TYPE_BUY_STOP;
         else
            ok = !okType;
        }
      else
        {
         if(entry > bid)
            ok = okType && t == ORDER_TYPE_SELL_LIMIT;
         else if(entry < bid)
            ok = okType && t == ORDER_TYPE_SELL_STOP;
         else
            ok = !okType;
        }
      ok = ok && (AiIsBuyType(t) == (side == AI_BUY));
      if(!Expect(ok, fails))
         Detail(suite, ((side == AI_BUY) ? "buy" : "sell") + (pending ? " pending" : " market") + ", entry " + D(entry) +
                ", bid " + D(bid) + ", ask " + D(ask) + " gave " + AiOrderTypeName(t) + (okType ? "" : " (refused)"));
     }
   Row(suite, n, fails);
  }

// AiCheckStops against an independent version written in whole points.
void SuiteStopsOracle(const int n)
  {
   string suite = "SL/TP checks against a whole-point reference";
   int fails = 0;
   int cases = 0;
   for(int i = 0; i < n; i++)
     {
      AiSpec s;
      RandomSpec(s);
      s.tickSize = s.point;
      int bidPts = RndInt(1000, 2000000);
      int askPts = bidPts + RndInt(0, 50);
      int side = RndChance(2) ? AI_BUY : AI_SELL;
      bool pending = RndChance(2);
      int entryPts = pending ? bidPts + RndInt(-500, 500) : ((side == AI_BUY) ? askPts : bidPts);
      bool okType = false;
      ENUM_ORDER_TYPE type = AiResolveType(side, pending, entryPts * s.point, bidPts * s.point, askPts * s.point, okType);
      if(!okType)
         continue;   // a pending entry exactly at the market has no type to check
      int slPts = RndChance(5) ? 0 : entryPts + RndInt(-400, 400);
      int tpPts = RndChance(5) ? 0 : entryPts + RndInt(-400, 400);
      bool buy = (side == AI_BUY);
      int minPts = MathMax(s.stopsLevel, 1);
      bool expectOk = true;
      if(slPts > 0 && (buy ? slPts >= entryPts : slPts <= entryPts))
         expectOk = false;
      if(tpPts > 0 && (buy ? tpPts <= entryPts : tpPts >= entryPts))
         expectOk = false;
      if(expectOk && pending)
        {
         int marketPts = buy ? askPts : bidPts;
         if(MathAbs(entryPts - marketPts) < minPts)
            expectOk = false;
         if(slPts > 0 && MathAbs(entryPts - slPts) < minPts)
            expectOk = false;
         if(tpPts > 0 && MathAbs(tpPts - entryPts) < minPts)
            expectOk = false;
        }
      else if(expectOk)
        {
         if(buy)
           {
            if(slPts > 0 && bidPts - slPts < minPts)
               expectOk = false;
            if(tpPts > 0 && tpPts - bidPts < minPts)
               expectOk = false;
           }
         else
           {
            if(slPts > 0 && slPts - askPts < minPts)
               expectOk = false;
            if(tpPts > 0 && askPts - tpPts < minPts)
               expectOk = false;
           }
        }
      string got = AiCheckStops(s, type, entryPts * s.point, slPts * s.point, tpPts * s.point, bidPts * s.point, askPts * s.point);
      cases++;
      if(!Expect((got == "") == expectOk, fails))
         Detail(suite, AiOrderTypeName(type) + " entry " + IntegerToString(entryPts) + ", SL " + IntegerToString(slPts) + ", TP " +
                IntegerToString(tpPts) + ", bid " + IntegerToString(bidPts) + ", ask " + IntegerToString(askPts) + " pts, stops level " +
                IntegerToString(s.stopsLevel) + ": expected " + (expectOk ? "pass" : "refusal") + ", got \"" + got + "\"");
     }
   Row(suite, cases, fails);
  }

// AiCheckModify against an independent version written in whole points: a position's levels count
// from the market, a pending order keeps its type, and the freeze level applies to what the server
// has now.
void SuiteModifyOracle(const int n)
  {
   string suite = "Changes to open trades against a whole-point reference";
   int fails = 0;
   int cases = 0;
   for(int i = 0; i < n; i++)
     {
      AiSpec s;
      RandomSpec(s);
      s.tickSize = s.point;
      s.tradeMode = SYMBOL_TRADE_MODE_FULL;
      s.freezeLevel = RndChance(3) ? RndInt(1, 100) : 0;
      int bidPts = RndInt(1000, 2000000);
      int askPts = bidPts + RndInt(0, 50);
      int side = RndChance(2) ? AI_BUY : AI_SELL;
      bool buy = (side == AI_BUY);
      AiLive l;
      ZeroMemory(l);
      l.ticket = 1;
      l.side = side;
      l.lots = 1.0;
      l.isOrder = RndChance(2);
      int openPts = bidPts + RndInt(-500, 500);
      int newOpenPts = openPts;
      if(l.isOrder)
        {
         bool okType = false;
         l.type = AiResolveType(side, true, openPts * s.point, bidPts * s.point, askPts * s.point, okType);
         if(!okType)
            continue;   // an order exactly at the market has no type
         if(!RndChance(3))
            newOpenPts = bidPts + RndInt(-500, 500);
        }
      else
         l.type = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      int oldSlPts = RndChance(4) ? 0 : openPts + RndInt(-400, 400);
      int oldTpPts = RndChance(4) ? 0 : openPts + RndInt(-400, 400);
      int slPts = RndChance(5) ? 0 : newOpenPts + RndInt(-400, 400);
      int tpPts = RndChance(5) ? 0 : newOpenPts + RndInt(-400, 400);
      l.open = openPts * s.point;
      l.sl = oldSlPts * s.point;
      l.tp = oldTpPts * s.point;

      int minPts = MathMax(s.stopsLevel, 1);
      int fz = s.freezeLevel;
      bool expectOk = true;
      if(fz > 0)
        {
         if(l.isOrder)
            expectOk = (MathAbs(openPts - (buy ? askPts : bidPts)) >= fz);
         else if(buy)
            expectOk = !((oldSlPts > 0 && bidPts - oldSlPts < fz) || (oldTpPts > 0 && oldTpPts - bidPts < fz));
         else
            expectOk = !((oldSlPts > 0 && oldSlPts - askPts < fz) || (oldTpPts > 0 && askPts - oldTpPts < fz));
        }
      if(expectOk && l.isOrder)
        {
         bool keepsType = false;
         if(l.type == ORDER_TYPE_BUY_LIMIT)
            keepsType = (newOpenPts < askPts);
         else if(l.type == ORDER_TYPE_BUY_STOP)
            keepsType = (newOpenPts > askPts);
         else if(l.type == ORDER_TYPE_SELL_LIMIT)
            keepsType = (newOpenPts > bidPts);
         else
            keepsType = (newOpenPts < bidPts);
         int marketPts = buy ? askPts : bidPts;
         if(!keepsType)
            expectOk = false;
         else if(slPts > 0 && (buy ? slPts >= newOpenPts : slPts <= newOpenPts))
            expectOk = false;
         else if(tpPts > 0 && (buy ? tpPts <= newOpenPts : tpPts >= newOpenPts))
            expectOk = false;
         else if(MathAbs(newOpenPts - marketPts) < minPts)
            expectOk = false;
         else if(slPts > 0 && MathAbs(newOpenPts - slPts) < minPts)
            expectOk = false;
         else if(tpPts > 0 && MathAbs(tpPts - newOpenPts) < minPts)
            expectOk = false;
        }
      else if(expectOk)
        {
         if(buy)
           {
            if(slPts > 0 && bidPts - slPts < minPts)
               expectOk = false;
            if(tpPts > 0 && tpPts - bidPts < minPts)
               expectOk = false;
           }
         else
           {
            if(slPts > 0 && slPts - askPts < minPts)
               expectOk = false;
            if(tpPts > 0 && askPts - tpPts < minPts)
               expectOk = false;
           }
        }
      string got = AiCheckModify(s, l, newOpenPts * s.point, slPts * s.point, tpPts * s.point, bidPts * s.point, askPts * s.point);
      cases++;
      if(!Expect((got == "") == expectOk, fails))
         Detail(suite, (l.isOrder ? AiOrderTypeName(l.type) : (buy ? "buy position" : "sell position")) + " open " + IntegerToString(openPts) + " -> " +
                IntegerToString(newOpenPts) + ", SL " + IntegerToString(oldSlPts) + " -> " + IntegerToString(slPts) + ", TP " + IntegerToString(oldTpPts) +
                " -> " + IntegerToString(tpPts) + ", bid " + IntegerToString(bidPts) + ", ask " + IntegerToString(askPts) + " pts, stops level " +
                IntegerToString(s.stopsLevel) + ", freeze level " + IntegerToString(s.freezeLevel) + ": expected " + (expectOk ? "pass" : "refusal") +
                ", got \"" + got + "\"");
     }
   Row(suite, cases, fails);
  }

// Every remembered SL/TP survives being written to the recall file and read back.
void SuiteMemoryRoundTrip(const int n)
  {
   string suite = "Recall records written and read back";
   int fails = 0;
   for(int i = 0; i < n; i++)
     {
      AiMem a;
      ZeroMemory(a);
      a.t = (long)RndInt(0, 2000000000);
      a.side = RndChance(2) ? AI_BUY : AI_SELL;
      a.slMode = RndChance(2) ? AI_LEVEL_PIPS : AI_LEVEL_PRICE;
      a.tpMode = RndInt(AI_LEVEL_PIPS, AI_LEVEL_RR);
      a.slDist = NormalizeDouble(MathPow(10.0, RndRange(-5.0, 4.0)), 8);
      a.tpDist = RndChance(5) ? 0.0 : NormalizeDouble(MathPow(10.0, RndRange(-5.0, 4.0)), 8);
      a.slPrice = NormalizeDouble(RndRange(0.0, 100000.0), 8);
      a.tpPrice = NormalizeDouble(RndRange(0.0, 100000.0), 8);
      a.tpR = NormalizeDouble(RndRange(0.0, 10.0), 2);
      string line = AiMemToLine(a);
      AiMem b;
      bool parsed = AiMemFromLine(line, b);
      bool ok = parsed && b.t == a.t && b.side == a.side && b.slMode == a.slMode && b.tpMode == a.tpMode &&
                Near(b.slDist, a.slDist, 1e-8 * (1.0 + a.slDist)) && Near(b.tpDist, a.tpDist, 1e-8 * (1.0 + a.tpDist)) &&
                Near(b.slPrice, a.slPrice, 1e-8 * (1.0 + a.slPrice)) && Near(b.tpPrice, a.tpPrice, 1e-8 * (1.0 + a.tpPrice)) &&
                Near(b.tpR, a.tpR, 0.005) && AiMemSame(a, b);
      if(!Expect(ok, fails))
         Detail(suite, "line \"" + line + "\" did not read back the same");
     }
   Row(suite, n, fails);
  }

// Damaged recall lines never produce a record with impossible values.
void SuiteMemoryFuzz(const int n)
  {
   string suite = "Damaged recall lines";
   int fails = 0;
   string chars = "t=;sldpxmr0123456789.-e +ab";
   int nc = StringLen(chars);
   AiMem base;
   ZeroMemory(base);
   base.t = 1729500000;
   base.side = AI_BUY;
   base.slDist = 0.0025;
   base.tpMode = AI_LEVEL_RR;
   base.tpDist = 0.005;
   base.tpR = 2.0;
   string valid = AiMemToLine(base);
   for(int i = 0; i < n; i++)
     {
      string line = "";
      if(RndChance(3))
        {
         // A real line with a few characters changed.
         line = valid;
         int changes = RndInt(1, 4);
         for(int c = 0; c < changes; c++)
           {
            int pos = RndInt(0, StringLen(line) - 1);
            line = StringSubstr(line, 0, pos) + StringSubstr(chars, RndInt(0, nc - 1), 1) + StringSubstr(line, pos + 1);
           }
        }
      else
        {
         int len = RndInt(0, 80);
         for(int j = 0; j < len; j++)
            line += StringSubstr(chars, RndInt(0, nc - 1), 1);
        }
      AiMem m;
      bool parsed = AiMemFromLine(line, m);
      bool ok = !parsed ||
                (MathIsValidNumber(m.slDist) && MathIsValidNumber(m.tpDist) && MathIsValidNumber(m.tpR) &&
                 m.slDist >= 0.0 && m.tpDist >= 0.0 && m.tpR >= 0.0 && (m.slDist > 0.0 || m.tpDist > 0.0) &&
                 (m.slMode == AI_LEVEL_PIPS || m.slMode == AI_LEVEL_PRICE) && m.tpMode >= AI_LEVEL_PIPS && m.tpMode <= AI_LEVEL_RR);
      if(!Expect(ok, fails))
         Detail(suite, "line \"" + line + "\" was accepted with impossible values");
     }
   Row(suite, n, fails);
  }

// Numbers typed into the panel read back as typed: comma or dot, spaces, % or $.
void SuiteParseNumber(const int n)
  {
   string suite = "Typed numbers";
   int fails = 0;
   string junk = "0123456789.,-%$ abc";
   int nj = StringLen(junk);
   for(int i = 0; i < n; i++)
     {
      if(RndChance(2))
        {
         int d = RndInt(0, 6);
         double v = NormalizeDouble(RndRange(-1000000.0, 1000000.0), d);
         string s = DoubleToString(v, d);
         if(RndChance(2))
            StringReplace(s, ".", ",");
         if(RndChance(3))
            s = "  " + s + " ";
         if(v >= 0.0 && RndChance(4))
            s = s + "%";
         else if(v >= 0.0 && RndChance(4))
            s = "$" + s;
         double got = 0.0;
         bool ok = AiParseNumber(s, got) && Near(got, v, 0.5 * MathPow(10.0, -d) + 1e-9);
         if(!Expect(ok, fails))
            Detail(suite, "\"" + s + "\" read as " + D(got) + ", expected " + D(v));
        }
      else
        {
         string s = "";
         int len = RndInt(0, 12);
         for(int j = 0; j < len; j++)
            s += StringSubstr(junk, RndInt(0, nj - 1), 1);
         double got = 0.0;
         bool parsed = AiParseNumber(s, got);
         bool hasDigit = false;
         for(int c = 0; c < StringLen(s); c++)
           {
            ushort ch = StringGetCharacter(s, c);
            if(ch >= '0' && ch <= '9')
               hasDigit = true;
           }
         bool ok = !parsed || (MathIsValidNumber(got) && hasDigit);
         if(!Expect(ok, fails))
            Detail(suite, "\"" + s + "\" was accepted as " + D(got));
        }
     }
   Row(suite, n, fails);
  }

bool ValidVk(const int vk)
  {
   return (vk >= 'A' && vk <= 'Z') || (vk >= '0' && vk <= '9') || vk == 13 || vk == 27 || vk == 32 || vk == 9 || (vk >= 112 && vk <= 123);
  }

// Every key the inputs can name parses to the right key code and modifiers, and matches only them.
void SuiteKeys(const int n)
  {
   string suite = "Hotkey names";
   int fails = 0;
   string names[];
   int codes[];
   int count = 0;
   for(int c = 'A'; c <= 'Z'; c++)
     {
      ArrayResize(names, count + 1);
      ArrayResize(codes, count + 1);
      names[count] = ShortToString((ushort)c);
      codes[count] = c;
      count++;
     }
   for(int c = '0'; c <= '9'; c++)
     {
      ArrayResize(names, count + 1);
      ArrayResize(codes, count + 1);
      names[count] = ShortToString((ushort)c);
      codes[count] = c;
      count++;
     }
   string words[6] = {"ENTER", "RETURN", "ESC", "ESCAPE", "SPACE", "TAB"};
   int wordCodes[6] = {13, 13, 27, 27, 32, 9};
   for(int w = 0; w < 6; w++)
     {
      ArrayResize(names, count + 1);
      ArrayResize(codes, count + 1);
      names[count] = words[w];
      codes[count] = wordCodes[w];
      count++;
     }
   for(int f = 1; f <= 12; f++)
     {
      ArrayResize(names, count + 1);
      ArrayResize(codes, count + 1);
      names[count] = "F" + IntegerToString(f);
      codes[count] = 111 + f;
      count++;
     }
   string junk = "ABCFSHIFTCTRL+12 x";
   int nj = StringLen(junk);
   for(int i = 0; i < n; i++)
     {
      if(RndChance(4))
        {
         string s = "";
         int len = RndInt(0, 14);
         for(int j = 0; j < len; j++)
            s += StringSubstr(junk, RndInt(0, nj - 1), 1);
         AiKey k;
         bool parsed = AiParseKey(s, k);
         bool ok = parsed ? ValidVk(k.vk) : (k.vk == 0);
         if(!Expect(ok, fails))
            Detail(suite, "\"" + s + "\" gave key code " + IntegerToString(k.vk));
         continue;
        }
      int idx = RndInt(0, count - 1);
      bool shift = RndChance(3);
      bool ctrl = RndChance(3);
      string spec = (ctrl ? "Ctrl+" : "") + (shift ? "SHIFT+" : "") + names[idx];
      if(RndChance(2))
         StringToLower(spec);
      AiKey k;
      bool ok = AiParseKey(spec, k) && k.vk == codes[idx] && k.shift == shift && k.ctrl == ctrl &&
                AiKeyMatch(k, codes[idx], shift, ctrl) && !AiKeyMatch(k, codes[idx], !shift, ctrl) && !AiKeyMatch(k, codes[idx], shift, !ctrl);
      if(ok && codes[idx] >= '0' && codes[idx] <= '9')
         ok = AiKeyMatch(k, 96 + (codes[idx] - '0'), shift, ctrl);
      if(!Expect(ok, fails))
         Detail(suite, "\"" + spec + "\" gave key code " + IntegerToString(k.vk) + (k.shift ? " +shift" : "") + (k.ctrl ? " +ctrl" : ""));
     }
   Row(suite, n, fails);
  }

// Pip sizes follow each convention; in the Trader convention forex and gold pips do not depend
// on how many digits the broker quotes, and recalled distances convert back to the same price.
void SuitePipSizes(const int n)
  {
   string suite = "Pip sizes and recalled distances";
   int fails = 0;
   string syms[11] = {"EURUSD", "EURUSDm", "USDJPY", "GBPJPYz", "XAUUSD", "XAUUSDm", "GOLD", "US30", "USTEC", "BTCUSD", "ETHUSDm"};
   for(int i = 0; i < n; i++)
     {
      string sym = syms[RndInt(0, 10)];
      int d = RndInt(0, 5);
      double point = MathPow(10.0, -d);
      int mode = RndInt(0, 2);
      double pip = AiPipSize(sym, d, point, mode);
      string up = sym;
      StringToUpper(up);
      bool gold = (StringFind(up, "XAU") == 0 || StringFind(up, "GOLD") >= 0);
      double expected = point;
      if(mode == AI_PIP_EXNESS)
         expected = point * 10.0;
      else if(mode == AI_PIP_TRADER)
        {
         if(gold)
            expected = 0.1;
         else if(d == 3 || d == 5)
            expected = point * 10.0;
        }
      bool ok = (pip > 0.0) && Near(pip, expected, 1e-12 * MathMax(1.0, expected));
      // A 5-digit and a 4-digit broker (or 3 and 2 for JPY) give the same Trader pip.
      if(ok && mode == AI_PIP_TRADER && !gold && (d == 3 || d == 5))
         ok = Near(pip, AiPipSize(sym, d - 1, MathPow(10.0, -(d - 1)), AI_PIP_TRADER), 1e-12);
      if(ok && mode == AI_PIP_TRADER && gold)
         ok = Near(pip, AiPipSize(sym, RndInt(0, 5), MathPow(10.0, -RndInt(0, 5)), AI_PIP_TRADER), 1e-12);
      // A distance recalled as pips (rounded to 0.1 pip) is back within a twentieth of a pip.
      double dist = MathPow(10.0, RndRange(-4.0, 3.0));
      double pips = NormalizeDouble(dist / pip, 1);
      if(ok)
         ok = MathAbs(pips * pip - dist) <= pip * 0.05 + 1e-12;
      if(!Expect(ok, fails))
         Detail(suite, sym + ", digits " + IntegerToString(d) + ", mode " + IntegerToString(mode) + ": pip " + D(pip) + ", expected " + D(expected));
     }
   Row(suite, n, fails);
  }

// Money shown on the panel reads back as the amount, with its sign and currency.
void SuiteMoney(const int n)
  {
   string suite = "Money formatting";
   int fails = 0;
   for(int i = 0; i < n; i++)
     {
      double v = RndChance(10) ? RndRange(-0.01, 0.01) : RndRange(-10000000.0, 10000000.0);
      int dec = RndChance(5) ? 0 : 2;
      string cur = RndChance(2) ? "USD" : "USC";
      bool withSign = RndChance(2);
      string s = AiMoney(v, cur, withSign, dec);
      string t = s;
      StringReplace(t, "$", "");
      StringReplace(t, ",", "");
      StringReplace(t, " " + cur, "");
      StringReplace(t, "+", "");
      double back = StringToDouble(t);
      double unit = MathPow(10.0, -dec);
      // Within one display unit: a value exactly halfway may round either way in the last digit.
      bool ok = Near(back, NormalizeDouble(v, dec), unit + 1e-6);
      if(cur == "USD")
         ok = ok && StringFind(s, "$") >= 0;
      else
         ok = ok && StringFind(s, " USC") == StringLen(s) - 4;
      if(v <= -unit)
         ok = ok && StringGetCharacter(s, 0) == '-';
      if(v >= unit && withSign)
         ok = ok && StringGetCharacter(s, 0) == '+';
      if(!Expect(ok, fails))
         Detail(suite, D(v) + " with " + IntegerToString(dec) + " decimals in " + cur + " showed \"" + s + "\"");
     }
   Row(suite, n, fails);
  }

// Full order plans on the chart's real symbol, with live prices and the real account: random sides,
// market and pending, SL/TP in every mode, every risk mode. A plan that may be sent must never
// break a rule; a plan that may not be sent must say why.
void SuiteLivePlans(const int n)
  {
   string suite = "Order plans on " + _Symbol + " (live prices)";
   AiSpec s;
   MqlTick tick;
   if(!AiLoadSpec(_Symbol, AI_PIP_TRADER, s) || !SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
     {
      g_table += suite + ": skipped, no symbol data or prices\r\n";
      return;
     }
   AiSettings cfg;
   ZeroMemory(cfg);
   cfg.maxRiskPct = 5.0;
   cfg.requireSL = true;
   cfg.requireTP = true;
   int fails = 0;
   int valid = 0;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   for(int i = 0; i < n; i++)
     {
      AiInput in;
      ZeroMemory(in);
      in.side = RndChance(2) ? AI_BUY : AI_SELL;
      in.pending = RndChance(3);
      double market = (in.side == AI_BUY) ? tick.ask : tick.bid;
      if(in.pending)
         in.entry = MathMax(s.tickSize, market + RndRange(-300.0, 300.0) * s.pipSize);
      double entryGuess = in.pending ? in.entry : market;
      if(RndChance(5))
        {
         // SL as a price; one in ten on the wrong side on purpose.
         in.slMode = AI_LEVEL_PRICE;
         double dir = RndChance(10) ? 1.0 : -1.0;
         in.slValue = MathMax(s.tickSize, entryGuess + dir * in.side * RndRange(1.0, 500.0) * s.pipSize);
        }
      else
        {
         in.slMode = AI_LEVEL_PIPS;
         in.slValue = RndChance(30) ? 0.0 : RndRange(0.5, 500.0);
        }
      int tpPick = RndInt(0, 2);
      if(tpPick == 0)
        {
         in.tpMode = AI_LEVEL_PIPS;
         in.tpValue = RndChance(30) ? 0.0 : RndRange(0.5, 1000.0);
        }
      else if(tpPick == 1)
        {
         in.tpMode = AI_LEVEL_RR;
         in.tpValue = RndRange(0.2, 5.0);
        }
      else
        {
         in.tpMode = AI_LEVEL_PRICE;
         double dir = RndChance(10) ? -1.0 : 1.0;
         in.tpValue = MathMax(s.tickSize, entryGuess + dir * in.side * RndRange(1.0, 1000.0) * s.pipSize);
        }
      int riskPick = RndInt(0, 2);
      in.riskMode = riskPick;
      if(riskPick == AI_RISK_PERCENT)
         in.riskValue = RndRange(0.05, 6.0);
      else if(riskPick == AI_RISK_MONEY)
         in.riskValue = RndRange(1.0, 500.0);
      else
         in.riskValue = s.volMin * RndInt(1, 50);
      in.riskBase = RndInt(0, 1);
      cfg.commissionRT = RndChance(4) ? RndRange(0.0, 10.0) : 0.0;

      AiPlan p;
      AiBuildPlan(s, in, cfg, tick, p);
      bool ok = true;
      string why = "";
      if(p.valid)
        {
         valid++;
         bool buy = (in.side == AI_BUY);
         double k = p.lots / s.volStep;
         bool okType = false;
         ENUM_ORDER_TYPE expectType = AiResolveType(in.side, in.pending, p.entry, tick.bid, tick.ask, okType);
         if(p.err != "")
            why = "a plan that may be sent carries an error";
         else if(MathAbs(k - MathRound(k)) > 1e-6 || p.lots < s.volMin - 1e-9 || p.lots > s.volMax + 1e-9)
            why = "lot size " + D(p.lots) + " is off the volume grid";
         else if(p.sl <= 0.0 || p.tp <= 0.0)
            why = "SL or TP missing although both are required";
         else if(buy ? (p.sl >= p.entry || p.tp <= p.entry) : (p.sl <= p.entry || p.tp >= p.entry))
            why = "SL or TP on the wrong side";
         else if(AiCheckStops(s, p.type, p.entry, p.sl, p.tp, tick.bid, tick.ask) != "")
            why = "SL/TP break the stops level";
         else if(!okType || expectType != p.type)
            why = "order type " + AiOrderTypeName(p.type) + " does not match the entry";
         else if(p.riskPct > cfg.maxRiskPct + 1e-9)
            why = "risk " + D(p.riskPct) + "% is above the cap";
         // 0.0001 of slack: the lot floor's epsilon can round up by a millionth of a step.
         else if(in.riskMode == AI_RISK_PERCENT && p.riskMoney > p.base * in.riskValue / 100.0 + 1e-4)
            why = "risk " + D(p.riskMoney) + " is above the target " + D(p.base * in.riskValue / 100.0);
         else if(in.riskMode == AI_RISK_MONEY && p.riskMoney > in.riskValue + 1e-4)
            why = "risk " + D(p.riskMoney) + " is above the target " + D(in.riskValue);
         else if(p.margin > freeMargin + 1e-6)
            why = "margin " + D(p.margin) + " is above the free margin";
         else if(MathAbs(p.riskPct - AiSafeDiv(p.riskMoney, p.base) * 100.0) > 1e-6)
            why = "risk % does not match the risk money";
         ok = (why == "");
        }
      else if(p.err == "")
        {
         ok = false;
         why = "a refused plan does not say why";
        }
      if(!Expect(ok, fails))
         Detail(suite, why + " | " + ((in.side == AI_BUY) ? "buy" : "sell") + (in.pending ? " pending @" + D(in.entry) : " market") +
                ", SL " + D(in.slValue) + " (mode " + IntegerToString(in.slMode) + "), TP " + D(in.tpValue) + " (mode " +
                IntegerToString(in.tpMode) + "), risk " + D(in.riskValue) + " (mode " + IntegerToString(in.riskMode) + ")");
     }
   g_table += suite + ": " + IntegerToString(n) + " cases (" + IntegerToString(valid) + " sendable), " +
              ((fails == 0) ? "all passed" : IntegerToString(fails) + " FAILED") + "\r\n";
  }

#endif
