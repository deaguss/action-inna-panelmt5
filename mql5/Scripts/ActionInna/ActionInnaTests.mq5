//+------------------------------------------------------------------+
//| ActionInnaTests.mq5                                              |
//| ActionInna's tests: worked examples, then generated scenarios    |
//| (about 124,000 per round). Drag onto any chart; the two live     |
//| suites use that chart's symbol and prices and send no orders.    |
//+------------------------------------------------------------------+
#property copyright   "ActionInna, MIT licence"
#property link        "https://github.com/deaguss/action-inna-panelmt5"
#property version     "1.10"
#property script_show_inputs

#include "Scenarios.mqh"

input uint InpSeed   = 20261021; // Seed (the same seed replays the same scenarios)
input int  InpRounds = 1;        // Rounds (one round is about 124,000 scenarios)

void TestSteps()
  {
   Check(AiStepDigits(0.01) == 2, "StepDigits 0.01");
   Check(AiStepDigits(0.25) == 2, "StepDigits 0.25");
   Check(AiStepDigits(1.0) == 0, "StepDigits 1");
   Check(AiStepDigits(0.001) == 3, "StepDigits 0.001");
   Check(Near(AiFloorToStep(0.39999999999999997, 0.01), 0.40), "FloorToStep ignores float noise");
   Check(Near(AiFloorToStep(0.389, 0.01), 0.38), "FloorToStep rounds down");
   Check(Near(AiFloorToStep(1.26, 0.25), 1.25), "FloorToStep on 0.25");

   AiSpec idx;
   ZeroMemory(idx);
   idx.digits = 2;
   idx.point = 0.01;
   idx.tickSize = 0.25;
   Check(Near(AiNormPrice(idx, 18000.13), 18000.25), "NormPrice rounds to a 0.25 tick (up)");
   Check(Near(AiNormPrice(idx, 18000.12), 18000.00), "NormPrice rounds to a 0.25 tick (down)");
  }

void TestPips()
  {
   Check(Near(AiPipSize("EURUSD", 5, 0.00001, AI_PIP_TRADER), 0.0001), "pip EURUSD trader");
   Check(Near(AiPipSize("EURUSDm", 5, 0.00001, AI_PIP_EXNESS), 0.0001), "pip EURUSDm exness");
   Check(Near(AiPipSize("USDJPY", 3, 0.001, AI_PIP_TRADER), 0.01), "pip USDJPY trader");
   Check(Near(AiPipSize("XAUUSDm", 3, 0.001, AI_PIP_TRADER), 0.1), "pip gold trader = 0.1");
   Check(Near(AiPipSize("XAUUSDm", 3, 0.001, AI_PIP_EXNESS), 0.01), "pip gold exness = 0.01");
   Check(Near(AiPipSize("US30m", 1, 0.1, AI_PIP_EXNESS), 1.0), "pip US30 exness = 1");
   Check(Near(AiPipSize("BTCUSD", 2, 0.01, AI_PIP_POINT), 0.01), "pip in points mode");
   Check(Near(AiPipSize("USTEC", 2, 0.01, AI_PIP_TRADER), 0.01), "pip 2-digit index trader = 1 point");
   Check(Near(AiPipSize("#XAUUSD", 2, 0.01, AI_PIP_TRADER), 0.1), "gold with a # prefix is still gold");
   Check(Near(AiPipSize("XAUUSD.r", 3, 0.001, AI_PIP_TRADER), 0.1), "gold with a .r suffix is still gold");
   Check(Near(AiPipSize("SPOTAU", 2, 0.01, AI_PIP_TRADER, "XAU"), 0.1), "gold known by its base currency only");
   Check(Near(AiPipSize("EURUSD.pro", 5, 0.00001, AI_PIP_TRADER, "EUR"), 0.0001), "forex with a suffix keeps its pip");
  }

void TestOrderTypes()
  {
   bool ok = false;
   Check(AiResolveType(AI_BUY, true, 1.08300, 1.08480, 1.08500, ok) == ORDER_TYPE_BUY_LIMIT && ok, "buy below the ask is a buy limit");
   Check(AiResolveType(AI_BUY, true, 1.08700, 1.08480, 1.08500, ok) == ORDER_TYPE_BUY_STOP && ok, "buy above the ask is a buy stop");
   Check(AiResolveType(AI_SELL, true, 1.08700, 1.08480, 1.08500, ok) == ORDER_TYPE_SELL_LIMIT && ok, "sell above the bid is a sell limit");
   Check(AiResolveType(AI_SELL, true, 1.08300, 1.08480, 1.08500, ok) == ORDER_TYPE_SELL_STOP && ok, "sell below the bid is a sell stop");
   Check(AiResolveType(AI_BUY, false, 0.0, 1.08480, 1.08500, ok) == ORDER_TYPE_BUY && ok, "market buy");
   Check(AiResolveType(AI_SELL, false, 0.0, 1.08480, 1.08500, ok) == ORDER_TYPE_SELL && ok, "market sell");
   AiResolveType(AI_BUY, true, 1.08500, 1.08480, 1.08500, ok);
   Check(!ok, "pending entry at the market price is refused");
  }

void TestStops()
  {
   AiSpec fx;
   ZeroMemory(fx);
   fx.digits = 5;
   fx.point = 0.00001;
   fx.tickSize = 0.00001;
   fx.stopsLevel = 30;
   fx.pipSize = 0.0001;
   fx.pipPoints = 10;
   // Market buy at ask 1.08500, bid 1.08480, stops level 30 points.
   Check(AiCheckStops(fx, ORDER_TYPE_BUY, 1.08500, 1.08450, 0.0, 1.08480, 1.08500) == "", "SL exactly at the stops level passes");
   Check(AiCheckStops(fx, ORDER_TYPE_BUY, 1.08500, 1.08451, 0.0, 1.08480, 1.08500) != "", "SL inside the stops level fails");
   Check(AiCheckStops(fx, ORDER_TYPE_BUY, 1.08500, 0.0, 1.08510, 1.08480, 1.08500) == "", "TP exactly at the stops level passes");
   Check(AiCheckStops(fx, ORDER_TYPE_BUY, 1.08500, 0.0, 1.08509, 1.08480, 1.08500) != "", "TP inside the stops level fails");
   Check(AiCheckStops(fx, ORDER_TYPE_SELL, 1.08480, 1.08470, 0.0, 1.08480, 1.08500) != "", "sell SL below the entry is the wrong side");
   Check(AiCheckStops(fx, ORDER_TYPE_BUY_LIMIT, 1.08300, 1.08100, 1.08700, 1.08480, 1.08500) == "", "buy limit with room passes");
   Check(AiCheckStops(fx, ORDER_TYPE_BUY_LIMIT, 1.08490, 1.08100, 1.08700, 1.08480, 1.08500) != "", "buy limit too close to the ask fails");
   fx.stopsLevel = 0;
   Check(AiCheckStops(fx, ORDER_TYPE_BUY, 1.08500, 1.08479, 0.0, 1.08480, 1.08500) == "", "stops level 0: one point under the bid passes");
   Check(AiCheckStops(fx, ORDER_TYPE_BUY, 1.08500, 1.08490, 0.0, 1.08480, 1.08500) != "", "stops level 0: SL inside the spread fails");
  }

// Changes to open trades: a position's levels count from the market, a pending order keeps its type.
void TestModify()
  {
   AiSpec fx;
   ZeroMemory(fx);
   fx.digits = 5;
   fx.point = 0.00001;
   fx.tickSize = 0.00001;
   fx.stopsLevel = 30;
   fx.pipSize = 0.0001;
   fx.pipPoints = 10;
   fx.tradeMode = SYMBOL_TRADE_MODE_FULL;
   double bid = 1.08480;
   double ask = 1.08500;

   AiLive buy;
   ZeroMemory(buy);
   buy.ticket = 1;
   buy.side = AI_BUY;
   buy.type = ORDER_TYPE_BUY;
   buy.lots = 0.10;
   buy.open = 1.08000;
   buy.sl = 1.07750;
   buy.tp = 1.08900;
   Check(AiCheckModify(fx, buy, buy.open, 1.08000, buy.tp, bid, ask) == "", "position: stop moved to break-even passes");
   Check(AiCheckModify(fx, buy, buy.open, 1.08200, buy.tp, bid, ask) == "", "position: stop past the open price (locks in profit) passes");
   Check(AiCheckModify(fx, buy, buy.open, 1.08450, buy.tp, bid, ask) == "", "position: SL exactly at the stops level under the bid passes");
   Check(AiCheckModify(fx, buy, buy.open, 1.08460, buy.tp, bid, ask) != "", "position: SL inside the stops level fails");
   Check(AiCheckModify(fx, buy, buy.open, 1.08490, buy.tp, bid, ask) != "", "position: SL above the bid fails");
   Check(AiCheckModify(fx, buy, buy.open, buy.sl, 1.08500, bid, ask) != "", "position: TP inside the stops level fails");
   Check(AiCheckModify(fx, buy, buy.open, buy.sl, 1.08470, bid, ask) != "", "position: TP below the bid fails");

   AiLive sell = buy;
   sell.side = AI_SELL;
   sell.type = ORDER_TYPE_SELL;
   sell.open = 1.08800;
   sell.sl = 1.09000;
   sell.tp = 1.08000;
   Check(AiCheckModify(fx, sell, sell.open, 1.08530, sell.tp, bid, ask) == "", "sell position: SL exactly at the stops level over the ask passes");
   Check(AiCheckModify(fx, sell, sell.open, 1.08520, sell.tp, bid, ask) != "", "sell position: SL inside the stops level fails");

   AiLive lim = buy;
   lim.isOrder = true;
   lim.type = ORDER_TYPE_BUY_LIMIT;
   lim.open = 1.08300;
   lim.sl = 1.08100;
   lim.tp = 1.08700;
   Check(AiCheckModify(fx, lim, 1.08200, 1.08000, 1.08600, bid, ask) == "", "buy limit moved lower, SL/TP along, passes");
   Check(AiCheckModify(fx, lim, 1.08600, 1.08400, 1.09000, bid, ask) != "", "buy limit dragged above the ask fails");
   Check(AiCheckModify(fx, lim, 1.08490, 1.08290, 1.08890, bid, ask) != "", "buy limit too close to the ask fails");
   Check(AiCheckModify(fx, lim, 1.08300, 1.08350, 1.08700, bid, ask) != "", "pending SL on the wrong side of the entry fails");

   fx.freezeLevel = 50;
   AiLive nearTp = buy;
   nearTp.tp = 1.08510;
   Check(AiCheckModify(fx, nearTp, nearTp.open, 1.07700, nearTp.tp, bid, ask) != "", "a level inside the freeze level blocks every change");
   Check(AiCheckModify(fx, buy, buy.open, 1.07700, buy.tp, bid, ask) == "", "levels outside the freeze level can change");
   AiLive nearOrder = lim;
   nearOrder.open = 1.08460;
   Check(AiCheckModify(fx, nearOrder, 1.08300, 1.08100, 1.08700, bid, ask) != "", "a pending order inside the freeze level cannot move");
   fx.freezeLevel = 0;

   fx.orderFlags = SYMBOL_ORDER_MARKET | SYMBOL_ORDER_LIMIT | SYMBOL_ORDER_STOP | SYMBOL_ORDER_SL;
   Check(AiCheckModify(fx, buy, buy.open, buy.sl, buy.tp, bid, ask) != "", "a symbol without take profit refuses one");
   fx.orderFlags = 0;
   AiLive stopLimit = lim;
   stopLimit.type = ORDER_TYPE_BUY_STOP_LIMIT;
   Check(AiCheckModify(fx, stopLimit, stopLimit.open, stopLimit.sl, stopLimit.tp, bid, ask) != "", "stop-limit orders are left to MT5");

   Check(!AiModCapBlocks(5.0, 4.0, 400.0, 300.0, true), "cap: below the cap passes");
   Check(AiModCapBlocks(5.0, 6.0, 600.0, 300.0, true), "cap: widening a stop above the cap is blocked");
   Check(!AiModCapBlocks(5.0, 6.0, 600.0, 800.0, true), "cap: tightening a stop that is still above the cap passes");
   Check(!AiModCapBlocks(5.0, 6.0, 600.0, 0.0, false), "cap: adding a stop where there was none passes");
   Check(!AiModCapBlocks(0.0, 60.0, 6000.0, 300.0, true), "cap: switched off");

   double o = 1.08300;
   double sl = 1.08100;
   double tp = 1.08700;
   AiMoveEntry(fx, 1.08200, o, sl, tp);
   Check(Near(o, 1.08200, 1e-9) && Near(sl, 1.08000, 1e-9) && Near(tp, 1.08600, 1e-9), "entry move takes SL and TP along");
   sl = 0.0;
   AiMoveEntry(fx, 1.08400, o, sl, tp);
   Check(Near(o, 1.08400, 1e-9) && sl == 0.0 && Near(tp, 1.08800, 1e-9), "a missing SL stays missing when the entry moves");
   AiMoveEntry(fx, 0.0, o, sl, tp);
   Check(Near(o, 1.08400, 1e-9) && Near(tp, 1.08800, 1e-9), "an entry of zero changes nothing");
  }

// A market order that fills away from its planned entry: which of its SL and TP move, and where to.
void TestFollowFill()
  {
   AiSpec g;
   ZeroMemory(g);
   g.digits = 2;
   g.point = 0.01;
   g.tickSize = 0.01;
   g.pipSize = 0.1;
   double sl = 0.0;
   double tp = 0.0;
   // BUY gold planned at 2650.28, filled 0.30 worse at 2650.58; SL 50 pips, TP 2R.
   Check(AiFollowFill(g, AI_SLIP_FOLLOW, AI_BUY, 2650.28, 2650.58, AI_LEVEL_PIPS, AI_LEVEL_RR, 2.0, 2645.28, 2660.28, sl, tp) &&
         Near(sl, 2645.58, 1e-9) && Near(tp, 2660.58, 1e-9), "SL in pips and TP in R move with the fill");
   Check(AiFollowFill(g, AI_SLIP_FOLLOW, AI_BUY, 2650.28, 2650.58, AI_LEVEL_PRICE, AI_LEVEL_RR, 2.0, 2645.00, 2660.84, sl, tp) &&
         Near(sl, 2645.00, 1e-9) && Near(tp, 2661.74, 1e-9), "SL set as a price stays; TP in R counts from the fill and that SL");
   Check(AiFollowFill(g, AI_SLIP_FOLLOW, AI_BUY, 2650.28, 2650.58, AI_LEVEL_PIPS, AI_LEVEL_PRICE, 2.0, 2645.28, 2660.00, sl, tp) &&
         Near(sl, 2645.58, 1e-9) && Near(tp, 2660.00, 1e-9), "TP set as a price stays");
   Check(!AiFollowFill(g, AI_SLIP_KEEP_PRICES, AI_BUY, 2650.28, 2650.58, AI_LEVEL_PIPS, AI_LEVEL_RR, 2.0, 2645.28, 2660.28, sl, tp) &&
         Near(sl, 2645.28, 1e-9) && Near(tp, 2660.28, 1e-9), "keep prices: nothing moves");
   Check(AiFollowFill(g, AI_SLIP_KEEP_RISK, AI_BUY, 2650.28, 2650.58, AI_LEVEL_PRICE, AI_LEVEL_PRICE, 2.0, 2645.00, 2660.00, sl, tp) &&
         Near(sl, 2645.30, 1e-9) && Near(tp, 2660.30, 1e-9), "keep the planned risk: both move, even prices");
   Check(AiFollowFill(g, AI_SLIP_FOLLOW, AI_SELL, 2650.12, 2650.32, AI_LEVEL_PIPS, AI_LEVEL_PIPS, 2.0, 2655.12, 2640.12, sl, tp) &&
         Near(sl, 2655.32, 1e-9) && Near(tp, 2640.32, 1e-9), "a SELL filled 0.20 better: SL and TP move up with it");
   Check(!AiFollowFill(g, AI_SLIP_FOLLOW, AI_BUY, 2650.28, 2650.284, AI_LEVEL_PIPS, AI_LEVEL_PIPS, 2.0, 2645.28, 2660.28, sl, tp),
         "less than a tick of slippage moves nothing");
  }

// Object names of open trades: AI_O<ticket>#<level><part>.
void TestTradeObjectNames()
  {
   CAiOrderLines lines;
   ulong t = 0;
   int w = -1;
   string part = "";
   Check(lines.Parse(AI_O + "12345678#S", t, w, part) && t == (ulong)12345678 && w == 1 && part == "", "trade line name: ticket, level, line");
   Check(lines.Parse(AI_O + "9876543210#Tb", t, w, part) && t == (ulong)9876543210 && w == 2 && part == "b", "tag name with a ticket above 2^32");
   Check(lines.Parse(AI_O + "7#Ex", t, w, part) && t == (ulong)7 && w == 0 && part == "x", "entry tag text");
   Check(lines.Parse(AI_O + "9#Sg", t, w, part) && w == 1 && part == "g", "server-level line");
   Check(!lines.Parse(AI_P + "12#S", t, w, part), "panel objects are not trade objects");
   Check(!lines.Parse(AI_O + "12#Q", t, w, part), "an unknown level is refused");
   Check(!lines.Parse(AI_O + "#S", t, w, part), "a name without a ticket is refused");
   Check(!lines.Parse(AI_O + "12#", t, w, part), "a name without a level is refused");
   Check(!lines.Parse(AI_O + "0#S", t, w, part), "ticket 0 is refused");
  }

void TestLots()
  {
   AiSpec s;
   ZeroMemory(s);
   s.volMin = 0.01;
   s.volMax = 100.0;
   s.volStep = 0.01;
   s.volDigits = 2;
   int code = -1;
   // EURUSD, $10,000, 1% = $100, 25 pips = $250 per lot.
   Check(Near(AiLotsForRisk(100.0, 250.0, 0.0, s, code), 0.40) && code == AI_LOTS_OK, "1% of 10k with a 25-pip EURUSD stop = 0.40 lots");
   // With $7 round-turn commission: 100 / 257 = 0.389 -> 0.38 lots, risk 97.66.
   Check(Near(AiLotsForRisk(100.0, 250.0, 7.0, s, code), 0.38) && code == AI_LOTS_OK, "commission lowers the lot size");
   Check(Near(0.38 * 257.0, 97.66, 1e-6), "risk with commission is 97.66");
   // Gold: $1,000, 2% = $20, a $5 stop on 100 oz = $500 per lot.
   Check(Near(AiLotsForRisk(20.0, 500.0, 0.0, s, code), 0.04) && code == AI_LOTS_OK, "2% of 1k with a $5 gold stop = 0.04 lots");
   Check(AiLotsForRisk(1.0, 250.0, 0.0, s, code) == 0.0 && code == AI_LOTS_BELOW_MIN, "below the minimum lot");
   Check(AiLotsForRisk(0.0, 250.0, 0.0, s, code) == 0.0 && code == AI_LOTS_NO_RISK, "zero risk");
   Check(AiLotsForRisk(100.0, 0.0, 0.0, s, code) == 0.0 && code == AI_LOTS_NO_VALUE, "stop with no value");
   Check(Near(AiLotsForRisk(1e7, 250.0, 0.0, s, code), 100.0) && code == AI_LOTS_CAPPED, "capped at the maximum lot");
  }

void TestMemory()
  {
   AiMem a;
   ZeroMemory(a);
   a.t = 1729500000;
   a.side = AI_BUY;
   a.slMode = AI_LEVEL_PIPS;
   a.slDist = 0.0025;
   a.slPrice = 1.0837;
   a.tpMode = AI_LEVEL_RR;
   a.tpDist = 0.0050;
   a.tpPrice = 1.0912;
   a.tpR = 2.0;
   AiMem b;
   Check(AiMemFromLine(AiMemToLine(a), b) && AiMemSame(a, b) && b.t == a.t && Near(b.slPrice, a.slPrice, 1e-8) && Near(b.slDist, 0.0025, 1e-10),
         "memory line round trip");
   Check(!AiMemFromLine("garbage", b), "a damaged line is skipped");
   Check(!AiMemFromLine("t=1;side=1;slm=0;sld=-5", b), "a negative distance is skipped");

   AiMem arr[];
   AiMemPush(arr, a);
   AiMemPush(arr, a);
   Check(ArraySize(arr) == 1, "the same SL/TP is kept once");
   for(int i = 0; i < 12; i++)
     {
      AiMem m = a;
      m.slDist = 0.0010 + i * 0.0001;
      AiMemPush(arr, m);
     }
   Check(ArraySize(arr) == AI_MEM_MAX, "history keeps at most AI_MEM_MAX records");
   Check(ArraySize(arr) > 0 && Near(arr[0].slDist, 0.0021, 1e-10), "newest record comes first");

   AiMem p;
   Check(AiMemFill(p, AI_BUY, 1.08500, 1.08250, 1.09000, 0) && Near(p.slDist, 0.0025, 1e-10) && Near(p.tpR, 2.0, 1e-6), "record from an order");
   Check(!AiMemFill(p, AI_BUY, 1.08500, 1.08600, 0.0, 0), "a stop on the profit side is not a stop distance");

   // The recall fix: a $5 gold stop is stored as 5.0 in price. It reads back as 50 trader pips
   // whether the broker quotes gold with 2 or 3 digits (stored as points it would be 500 or 5000).
   AiMem g;
   Check(AiMemFill(g, AI_SELL, 2650.00, 2655.00, 0.0, 0) && Near(g.slDist, 5.0, 1e-9), "gold stop stored as a price distance");
   Check(Near(g.slDist / AiPipSize("XAUUSD", 2, 0.01, AI_PIP_TRADER), 50.0, 1e-9) &&
         Near(g.slDist / AiPipSize("XAUUSD", 3, 0.001, AI_PIP_TRADER), 50.0, 1e-9), "same gold stop in pips at 2- and 3-digit brokers");
  }

void TestParsing()
  {
   double v = 0.0;
   Check(AiParseNumber("1,5", v) && Near(v, 1.5), "comma as decimal separator");
   Check(AiParseNumber(" 25 ", v) && Near(v, 25.0), "spaces around a number");
   Check(AiParseNumber("2%", v) && Near(v, 2.0), "percent sign");
   Check(!AiParseNumber("abc", v), "letters are refused");
   Check(!AiParseNumber("1.2.3", v), "two decimal points are refused");
   Check(!AiParseNumber("", v), "empty text is refused");
   Check(AiTrimZeros("1.50") == "1.5" && AiTrimZeros("2.00") == "2" && AiTrimZeros("10") == "10", "trailing zeros");
   Check(AiGroup(12345.6, 2) == "12,345.60", "thousands separator");
   Check(AiMoney(-100.0, "USD", false, 2) == "-$100.00", "money in USD");
   Check(AiMoney(200.0, "USC", true, 2) == "+200.00 USC", "money in another currency");
   Check(AiMoney(-1234.4, "JPY", false, 0) == "-1,234 JPY", "money in a currency without decimals");
   Check(AiMoney(1.5, "EUR") == AiMoney(1.5, "EUR", false, AiMoneyDigits()), "money uses the account currency's decimals by default");
  }

void TestKeys()
  {
   AiKey k;
   Check(AiParseKey("B", k) && k.vk == 'B' && !k.shift && !k.ctrl, "parse B");
   Check(AiParseKey("shift+enter", k) && k.vk == 13 && k.shift, "parse SHIFT+ENTER");
   Check(AiParseKey("CTRL+1", k) && k.vk == '1' && k.ctrl, "parse CTRL+1");
   Check(AiParseKey("F5", k) && k.vk == 116, "parse F5");
   Check(AiParseKey("esc", k) && k.vk == 27, "parse ESC");
   Check(!AiParseKey("", k) && k.vk == 0, "an empty key is disabled");
   Check(!AiParseKey("ALT+B", k), "ALT is not offered");
   AiParseKey("1", k);
   Check(AiKeyMatch(k, 97, false, false), "number-pad 1 matches 1");
   Check(!AiKeyMatch(k, 49, true, false), "SHIFT+1 does not match 1");
  }

void OnStart()
  {
   ulong started = GetMicrosecondCount();
   g_rng = (InpSeed == 0) ? 1 : InpSeed;
   int rounds = MathMax(1, InpRounds);

   TestSteps();
   TestPips();
   TestOrderTypes();
   TestStops();
   TestModify();
   TestFollowFill();
   TestTradeObjectNames();
   TestLots();
   TestMemory();
   TestParsing();
   TestKeys();
   Row("Worked examples", g_pass + g_fail, g_fail);

   SuiteFloorToStep(10000 * rounds);
   SuiteLotsForRisk(10000 * rounds);
   SuiteNormPrice(10000 * rounds);
   SuiteResolveType(10000 * rounds);
   SuiteStopsOracle(10000 * rounds);
   SuiteModifyOracle(10000 * rounds);
   SuiteEntryShift(10000 * rounds);
   SuiteFollowFill(10000 * rounds);
   SuiteMemoryRoundTrip(5000 * rounds);
   SuiteMemoryFuzz(5000 * rounds);
   SuiteParseNumber(10000 * rounds);
   SuiteKeys(5000 * rounds);
   SuitePipSizes(10000 * rounds);
   SuiteMoney(5000 * rounds);
   SuiteLivePlans(2000 * rounds);
   SuiteLiveModify(2000 * rounds);

   double seconds = (double)(GetMicrosecondCount() - started) / 1000000.0;
   string summary = "ActionInna tests: " + IntegerToString(g_pass + g_fail) + " checks, " + IntegerToString(g_pass) + " passed, " +
                    IntegerToString(g_fail) + " failed (seed " + IntegerToString(InpSeed) + ", " + IntegerToString(rounds) +
                    " round" + ((rounds == 1) ? "" : "s") + ", " + DoubleToString(seconds, 1) + " s)";
   Print(summary);
   string text = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + "  MT5 build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)) +
                 ", chart " + _Symbol + "\r\n" + summary + "\r\n\r\n" + g_table;
   if(g_report != "")
      text += "\r\nFirst failures:\r\n" + g_report;
   FolderCreate(AI_FILES_DIR, 0);
   // The alert names the report's full path (or why it could not be written), so a report that
   // went to another terminal, or nowhere, is visible without opening the Experts tab.
   string path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + AI_FILES_DIR + "\\test-results.txt";
   string where = "Report: " + path;
   ResetLastError();
   int h = FileOpen(AI_FILES_DIR + "\\test-results.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h != INVALID_HANDLE)
     {
      FileWriteString(h, text);
      FileClose(h);
     }
   else
      where = "Could not write the report (error " + IntegerToString(GetLastError()) + "): " + path;
   Print(where);
   Alert(summary + " | " + where);
  }
//+------------------------------------------------------------------+
