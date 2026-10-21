// Drag-and-confirm scenarios for open trades, run against the real CAiApp in a fake MT5. Each one
// does what a trader does (drag, release, click, type, press keys) or what the server does (close,
// change, refuse), and checks what reaches the server. A random fuzz runs the same moves in any
// order. Exits with 1 when any check fails.
//   app [fuzz-iterations] [seed]
#include <random>
#include "mql.h"
#include <ActionInna/App.mqh>

CAiApp g_app;   // a global, as in the EA: zeroed before its constructor runs

static int s_pass = 0;
static int s_fail = 0;
static std::string s_case;
static bool s_confirming = false;   // a Confirm click or key is being handled: a request may go out
static std::vector<std::string> s_bad;   // requests the server should never have seen
static int s_checked = 0;               // changes the server checked

static void Expect_(bool ok, const std::string &what, int line)
  {
   if(ok)
     {
      s_pass++;
      return;
     }
   s_fail++;
   if(s_fail <= 60)
      printf("FAIL [%s] %s (app.cpp:%d)\n", s_case.c_str(), what.c_str(), line);
  }
#define EXPECT(cond, what) Expect_((cond), (what), __LINE__)

//--- reading the fake chart --------------------------------------------------
static const std::string kP = "AINNA_P_";
static std::string Obj(ulong t, const char *part) { return "AINNA_O_" + std::to_string(t) + "#" + part; }
static FakeObj *Get(const std::string &n) { auto it = g_fake.objs.find(n); return it == g_fake.objs.end() ? nullptr : &it->second; }
static bool Exists(const std::string &n) { return Get(n) != nullptr; }
static bool Shown(const std::string &n) { FakeObj *o = Get(n); return o && o->i[OBJPROP_TIMEFRAMES * 16] != OBJ_NO_PERIODS; }
static double PriceOf(const std::string &n) { FakeObj *o = Get(n); return o ? o->d[OBJPROP_PRICE * 16] : 0.0; }
static void SetPriceOf(const std::string &n, double p) { if(FakeObj *o = Get(n)) o->d[OBJPROP_PRICE * 16] = p; }
static bool Selectable(const std::string &n) { FakeObj *o = Get(n); return o && o->i[OBJPROP_SELECTABLE * 16] != 0; }
static bool Selected(const std::string &n) { FakeObj *o = Get(n); return o && o->i[OBJPROP_SELECTED * 16] != 0; }
static std::string TextOf(const std::string &n) { FakeObj *o = Get(n); return o ? o->s[OBJPROP_TEXT] : std::string(); }
static int OrderOf(const std::string &n) { FakeObj *o = Get(n); return o ? o->order : 0; }
static bool Has(const std::string &hay, const std::string &needle) { return hay.find(needle) != std::string::npos; }
static bool Near(double a, double b, double eps = 1e-9) { return std::fabs(a - b) <= eps; }
static bool CardOpen() { return Shown(kP + "MODOK#bg"); }
static std::string CardStatus() { return TextOf(kP + "XMST1#t") + " " + TextOf(kP + "XMST2#t"); }
static std::string PanelStatus() { return TextOf(kP + "XST1#t") + " " + TextOf(kP + "XST2#t"); }

// Highest creation number among the trade objects drawn in front (server-level lines sit behind).
static int TopTradeObject()
  {
   int top = 0;
   for(auto &kv : g_fake.objs)
      if(kv.first.rfind("AINNA_O_", 0) == 0 && kv.first.back() != 'g')
         top = std::max(top, kv.second.order);
   return top;
  }
static int GhostCount()
  {
   int n = 0;
   for(auto &kv : g_fake.objs)
      if(kv.first.rfind("AINNA_O_", 0) == 0 && kv.first.back() == 'g')
         n++;
   return n;
  }

//--- what the trader and the terminal do -------------------------------------
static void Advance(int ms) { g_fake.us += (ulong)ms * 1000ULL; }
static void Event(int id, int64_t l, double d, const std::string &s)
  {
   int64_t lp = l;
   double dp = d;
   string sp(s);
   g_app.ChartEvent(id, lp, dp, sp);
  }
static void Refresh() { Advance(150); g_app.Timer(); }
static void Mouse(int x, int y, int buttons) { Advance(30); Event(CHARTEVENT_MOUSE_MOVE, x, y, std::to_string(buttons)); }
static int YOf(double price) { int x = 0, y = 0; ChartTimePriceToXY(0, 0, 0, price, x, y); return y; }
static bool IsConfirm(const std::string &n) { return n == kP + "MODOK#bg" || n == kP + "MODOK#tx" || n == kP + "CONFIRM#bg" || n == kP + "CONFIRM#tx"; }
static void Click(const std::string &n, int y = 300)
  {
   s_confirming = IsConfirm(n);
   Event(CHARTEVENT_OBJECT_CLICK, 400, y, n);
   s_confirming = false;
  }
static void Key(int vk)
  {
   s_confirming = (vk == 13 || vk == 32);
   Event(CHARTEVENT_KEYDOWN, vk, 1.0, "0");
   s_confirming = false;
  }
static void Type(const std::string &field, const std::string &text)
  {
   Click(field);
   if(FakeObj *o = Get(field))
      o->s[OBJPROP_TEXT] = text;
   Event(CHARTEVENT_OBJECT_ENDEDIT, 0, 0, field);
  }
enum DragMode { DRAG_BOTH, DRAG_POLL_ONLY, DRAG_EVENT_ONLY };
// What MT5 does when the trader drags a line: button down, the line follows the mouse (only when
// it is selectable), button up, then the drag event.
static void Drag(const std::string &n, double to, DragMode mode = DRAG_BOTH)
  {
   double from = PriceOf(n);
   bool movable = Selectable(n);
   if(mode != DRAG_EVENT_ONLY)
      Mouse(500, YOf(from), 1);
   for(int k = 1; k <= 3; k++)
     {
      double p = from + (to - from) * k / 3.0;
      if(movable)
         SetPriceOf(n, p);
      if(mode != DRAG_EVENT_ONLY)
         Mouse(500, YOf(p), 1);
     }
   if(mode != DRAG_EVENT_ONLY)
      Mouse(500, YOf(to), 0);
   if(mode != DRAG_POLL_ONLY && movable)
      Event(CHARTEVENT_OBJECT_DRAG, 0, 0, n);
  }

//--- setting up --------------------------------------------------------------
static AiSettings DefaultCfg()
  {
   AiSettings c;
   ZeroMemory(c);
   c.preset[0] = 1.0;
   c.preset[1] = 1.5;
   c.preset[2] = 2.0;
   c.riskBase = AI_BASE_EQUITY;
   c.maxRiskPct = 5.0;
   c.requireSL = true;
   c.requireTP = true;
   c.defaultSLPips = 20.0;
   c.defaultTPMode = AI_LEVEL_RR;
   c.defaultTPValue = 2.0;
   c.pipMode = AI_PIP_TRADER;
   c.autoRecall = true;
   c.pendingOffsetPips = 10.0;
   c.deviation = 10;
   c.comment = "ActionInna";
   c.manageOrders = true;
   c.hotkeys = true;
   c.keyBuy = "B";
   c.keySell = "S";
   c.keyConfirm = "ENTER";
   c.keyCancel = "ESC";
   c.keyRisk1 = "1";
   c.keyRisk2 = "2";
   c.keyRisk3 = "3";
   c.keyRiskC = "4";
   c.keyRecall = "R";
   c.keyPending = "P";
   c.keyCollapse = "H";
   c.hideOneClick = true;
   c.autoShift = true;
   c.showZones = true;
   c.theme = AI_THEME_AUTO;
   c.uiScale = 1.0;
   c.font = "Arial";
   c.fontSize = 9;
   return c;
  }

static void Setup(const std::string &name, bool manage = true)
  {
   s_case = name;
   g_app.Deinit(REASON_REMOVE);
   g_fake.Reset();
   g_app.cfg = DefaultCfg();
   g_app.cfg.manageOrders = manage;
   g_app.Init();
   Refresh();
  }

static void AddPos(ulong t, int type, double vol, double open, double sl, double tp)
  {
   g_fake.pos.push_back(FakePos{t, type, vol, open, sl, tp, 0.0, (int64_t)g_fake.time * 1000, g_fake.sym.name});
  }
static void AddOrd(ulong t, int type, double vol, double price, double sl, double tp, int typeTime = ORDER_TIME_GTC, datetime exp = 0,
                   double stoplimit = 0.0)
  {
   g_fake.ords.push_back(FakeOrd{t, type, vol, price, sl, tp, stoplimit, typeTime, exp, g_fake.sym.name});
  }
static FakePos *PosOf(ulong t) { for(auto &p : g_fake.pos) if(p.ticket == t) return &p; return nullptr; }
static FakeOrd *OrdOf(ulong t) { for(auto &o : g_fake.ords) if(o.ticket == t) return &o; return nullptr; }
static size_t Sent() { return g_fake.requests.size(); }
static const MqlTradeRequest &Last() { return g_fake.requests.back(); }

// Every change that reaches the server must have come from a Confirm, pass the checks against what
// the server has at that moment, keep both levels, and change something.
static void CheckRequest(const MqlTradeRequest &r)
  {
   s_checked++;
   if(!s_confirming)
      s_bad.push_back(s_case + ": a request went out without a Confirm click or key");
   if(r.action != TRADE_ACTION_SLTP && r.action != TRADE_ACTION_MODIFY)
      return;
   AiLive l;
   ZeroMemory(l);
   bool found = false;
   if(r.action == TRADE_ACTION_SLTP)
     {
      if(FakePos *p = PosOf(r.position))
        {
         found = true;
         l.side = (p->type == POSITION_TYPE_BUY) ? AI_BUY : AI_SELL;
         l.type = (p->type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         l.open = p->open;
         l.sl = p->sl;
         l.tp = p->tp;
         l.lots = p->volume;
        }
     }
   else if(FakeOrd *o = OrdOf(r.order))
     {
      found = true;
      l.isOrder = true;
      l.type = (ENUM_ORDER_TYPE)o->type;
      l.side = (o->type == ORDER_TYPE_BUY_LIMIT || o->type == ORDER_TYPE_BUY_STOP || o->type == ORDER_TYPE_BUY_STOP_LIMIT) ? AI_BUY : AI_SELL;
      l.open = o->price;
      l.sl = o->sl;
      l.tp = o->tp;
      l.lots = o->volume;
      if(r.type_time != o->typeTime || r.expiration != o->expiration)
         s_bad.push_back(s_case + ": a pending order's expiry was not kept");
      if(r.stoplimit != o->stoplimit)
         s_bad.push_back(s_case + ": a pending order's stop-limit price was not kept");
     }
   if(!found)
     {
      s_bad.push_back(s_case + ": a change was sent for a trade the server does not have");
      return;
     }
   AiSpec s;
   AiLoadSpec(_Symbol, AI_PIP_TRADER, s);
   double open = (r.action == TRADE_ACTION_MODIFY) ? r.price : l.open;
   string why = AiCheckModify(s, l, open, r.sl, r.tp, g_fake.sym.bid, g_fake.sym.ask);
   if(why != string(""))
      s_bad.push_back(s_case + ": sent a change the checks refuse: " + why.s);
   if((g_app.cfg.requireSL && r.sl <= 0.0) || (g_app.cfg.requireTP && r.tp <= 0.0))
      s_bad.push_back(s_case + ": sent a change without a required SL or TP");
   if(open == l.open && r.sl == l.sl && r.tp == l.tp)
      s_bad.push_back(s_case + ": sent a change that changes nothing");
   double half = s.point * 0.5;
   if(std::fabs(r.sl - AiNormPrice(s, r.sl)) > half || std::fabs(r.tp - AiNormPrice(s, r.tp)) > half || std::fabs(open - AiNormPrice(s, open)) > half)
      s_bad.push_back(s_case + ": sent a price off the tick grid");
  }

//--- scenarios ---------------------------------------------------------------
static void ScenarioChartLines()
  {
   Setup("MT5's own trade lines are handed over and back");
   EXPECT(g_fake.chartI[CHART_SHOW_TRADE_LEVELS] == 0, "MT5's own trade lines are hidden while the EA runs");
   EXPECT(g_fake.chartI[CHART_DRAG_TRADE_LEVELS] == 0, "dragging MT5's own trade lines is off while the EA runs");
   g_app.Deinit(REASON_CHARTCHANGE);
   g_app.Init();
   EXPECT(g_fake.chartI[CHART_SHOW_TRADE_LEVELS] == 0, "still hidden after a timeframe change");
   g_app.Deinit(REASON_REMOVE);
   EXPECT(g_fake.chartI[CHART_SHOW_TRADE_LEVELS] == 1 && g_fake.chartI[CHART_DRAG_TRADE_LEVELS] == 1, "MT5's own lines come back when the EA is removed");

   Setup("switched off: MT5's lines stay, no trade lines drawn", false);
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   EXPECT(g_fake.chartI[CHART_SHOW_TRADE_LEVELS] == 1 && g_fake.chartI[CHART_DRAG_TRADE_LEVELS] == 1, "MT5's own lines untouched");
   EXPECT(!Exists(Obj(101, "S")), "no trade lines of ActionInna's own");
  }

static void ScenarioLinesDrawn()
  {
   Setup("a position's lines and tags");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   EXPECT(Exists(Obj(101, "E")) && Exists(Obj(101, "S")) && Exists(Obj(101, "T")), "entry, SL and TP lines drawn");
   EXPECT(!Selectable(Obj(101, "E")), "a position's entry line cannot be dragged");
   EXPECT(Selectable(Obj(101, "S")) && Selected(Obj(101, "S")) && Selectable(Obj(101, "T")), "SL and TP lines are ready to drag");
   EXPECT(Near(PriceOf(Obj(101, "S")), 1.07750) && Near(PriceOf(Obj(101, "T")), 1.08900), "lines at the server's levels");
   EXPECT(Has(TextOf(Obj(101, "Sx")), "SL 1.07750 | -$25.00 (-0.25%)"), "SL tag with money and %: " + TextOf(Obj(101, "Sx")));
   EXPECT(Has(TextOf(Obj(101, "Tx")), "TP 1.08900 | +$90.00 (+0.90%)"), "TP tag with money and %: " + TextOf(Obj(101, "Tx")));
   EXPECT(Has(TextOf(Obj(101, "Ex")), "BUY 0.10 @ 1.08000 | +$48.00"), "entry tag with floating profit: " + TextOf(Obj(101, "Ex")));
   EXPECT(OrderOf(kP + "XBG#r") > TopTradeObject(), "the panel is drawn over the trade lines");
   EXPECT(!CardOpen() && GhostCount() == 0, "no card and no server-level lines before a drag");
  }

static void ScenarioDragConfirm()
  {
   Setup("drag SL, then confirm");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Mouse(500, YOf(1.07750), 1);
   SetPriceOf(Obj(101, "S"), 1.07650);
   Mouse(500, YOf(1.07650), 1);
   EXPECT(!CardOpen(), "the card waits while the line is held");
   EXPECT(Has(TextOf(Obj(101, "Sx")), "SL 1.07650 (was 1.07750) | -$35.00 (-0.35%)"), "the tag follows the drag: " + TextOf(Obj(101, "Sx")));
   Mouse(500, YOf(1.07650), 0);
   Event(CHARTEVENT_OBJECT_DRAG, 0, 0, Obj(101, "S"));
   EXPECT(CardOpen(), "the card opens when the line is let go");
   EXPECT(Sent() == 0, "a drag sends nothing");
   EXPECT(PosOf(101)->sl == 1.07750, "the server still has the old SL");
   EXPECT(Exists(Obj(101, "Sg")) && Near(PriceOf(Obj(101, "Sg")), 1.07750), "the server's SL is shown as a dotted line");
   EXPECT(Has(TextOf(kP + "XMTKT#t"), "#101"), "the card names the ticket");
   EXPECT(Has(TextOf(kP + "XMSLW#t"), "was 1.07750"), "the card shows the old SL");
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0, "Confirm right after the drop is ignored");
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1, "Confirm sends one request");
   if(Sent() == 1)
     {
      EXPECT(Last().action == TRADE_ACTION_SLTP && Last().position == 101, "a position change is TRADE_ACTION_SLTP for its ticket");
      EXPECT(Near(Last().sl, 1.07650) && Near(Last().tp, 1.08900) && Last().symbol == string("EURUSD"), "with the new SL and the TP kept");
     }
   EXPECT(PosOf(101)->sl == 1.07650, "the server has the new SL");
   EXPECT(!CardOpen() && GhostCount() == 0, "the card and the dotted line are gone");
   EXPECT(Has(PanelStatus(), "Changed #101: SL 1.07650"), "the panel says what changed: " + PanelStatus());
   Click(kP + "MODOK#bg");
   Key(13);
   EXPECT(Sent() == 1, "nothing more is sent");
  }

static void ScenarioCancel()
  {
   Setup("drag TP, cancel with Esc and with the button");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "T"), 1.09200);
   EXPECT(CardOpen(), "card open");
   Advance(350);
   Key(27);
   EXPECT(Sent() == 0 && !CardOpen(), "Esc closes the card and sends nothing");
   EXPECT(Near(PriceOf(Obj(101, "T")), 1.08900) && GhostCount() == 0, "the TP line goes back");
   Drag(Obj(101, "T"), 1.09300);
   Advance(350);
   Click(kP + "MODX#bg");
   EXPECT(Sent() == 0 && !CardOpen() && Near(PriceOf(Obj(101, "T")), 1.08900), "Cancel does the same");
   EXPECT(Has(PanelStatus(), "Nothing was sent"), "the panel says nothing was sent");
  }

static void ScenarioTwoLevelsOneRequest()
  {
   Setup("drag SL and TP, one request");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.07650);
   Drag(Obj(101, "T"), 1.09100);
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Near(Last().sl, 1.07650) && Near(Last().tp, 1.09100), "both levels in one request");
  }

static void ScenarioOtherTradeDropsFirst()
  {
   Setup("dragging another trade drops the first change");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   AddPos(102, POSITION_TYPE_SELL, 0.20, 1.09000, 1.09300, 1.08200);
   Refresh();
   Drag(Obj(101, "S"), 1.07650);
   Drag(Obj(102, "T"), 1.08100);
   EXPECT(Near(PriceOf(Obj(101, "S")), 1.07750), "the first trade's SL goes back");
   EXPECT(Has(TextOf(kP + "XMTKT#t"), "#102"), "the card is now for the second trade");
   EXPECT(Has(PanelStatus(), "change to #101 was dropped"), "the panel says the first change was dropped: " + PanelStatus());
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Last().position == 102 && Near(Last().tp, 1.08100) && Near(Last().sl, 1.09300), "only the second change is sent");
   EXPECT(PosOf(101)->sl == 1.07750, "the first trade is untouched");
  }

static void ScenarioPendingEntry()
  {
   Setup("a pending order's entry takes SL and TP along");
   datetime exp = g_fake.time + 86400;
   AddOrd(201, ORDER_TYPE_BUY_LIMIT, 0.10, 1.08300, 1.08100, 1.08700, ORDER_TIME_SPECIFIED, exp);
   Refresh();
   EXPECT(Selectable(Obj(201, "E")), "a pending order's entry can be dragged");
   Drag(Obj(201, "E"), 1.08200);
   EXPECT(Near(PriceOf(Obj(201, "S")), 1.08000) && Near(PriceOf(Obj(201, "T")), 1.08600), "SL and TP moved by the same distance");
   EXPECT(Exists(Obj(201, "Eg")) && Near(PriceOf(Obj(201, "Eg")), 1.08300), "the server's entry shown dotted");
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1, "one request");
   if(Sent() == 1)
     {
      EXPECT(Last().action == TRADE_ACTION_MODIFY && Last().order == 201, "a pending change is TRADE_ACTION_MODIFY for its ticket");
      EXPECT(Near(Last().price, 1.08200) && Near(Last().sl, 1.08000) && Near(Last().tp, 1.08600), "new entry, SL and TP");
      EXPECT(Last().type_time == ORDER_TIME_SPECIFIED && Last().expiration == exp, "the order keeps its expiry");
     }
  }

static void ScenarioRefusals()
  {
   Setup("changes the checks refuse are never sent");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   AddOrd(201, ORDER_TYPE_BUY_LIMIT, 0.10, 1.08300, 1.08100, 1.08700);
   Refresh();
   Drag(Obj(201, "E"), 1.08600);
   Advance(350);
   Click(kP + "MODOK#bg");
   Key(13);
   EXPECT(Sent() == 0, "a Buy Limit dragged above the market is not sent");
   EXPECT(Has(CardStatus(), "BUY LIMIT must stay below the market price"), "the card says why: " + CardStatus());
   Key(27);
   Drag(Obj(101, "S"), 1.08490);
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0, "a buy's SL above the bid is not sent");
   EXPECT(Has(CardStatus(), "Stop loss must stay below the price"), "the card says why: " + CardStatus());
   Key(27);
   Drag(Obj(101, "T"), 1.08470);
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0, "a buy's TP below the bid is not sent");
   Key(27);
   g_fake.sym.stops = 30;
   Drag(Obj(101, "S"), 1.08460);
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0 && Has(CardStatus(), "too close"), "a SL inside the stops level is not sent: sent " + std::to_string(Sent()) + ", " + CardStatus());
   Key(27);
   g_fake.sym.stops = 0;
  }

static void ScenarioBreakEven()
  {
   Setup("a stop past the open price is allowed");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.08100);
   EXPECT(Has(TextOf(Obj(101, "Sx")), "+$10.00"), "the SL tag shows the profit it locks in: " + TextOf(Obj(101, "Sx")));
   EXPECT(Has(TextOf(kP + "XRMRR#v"), "break-even or better"), "R:R says the stop is at break-even or better");
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Near(Last().sl, 1.08100), "sent");

   Setup("a sell's stop past the open price is allowed");
   AddPos(102, POSITION_TYPE_SELL, 0.10, 1.09000, 1.09300, 1.08200);
   Refresh();
   Drag(Obj(102, "S"), 1.08510);
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Near(Last().sl, 1.08510), "a sell's stop just above the ask is sent");
   Advance(800);
   Drag(Obj(102, "S"), 1.08495);
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1, "a sell's stop below the ask is not");
  }

static void ScenarioSafetyCap()
  {
   Setup("the safety cap blocks a bigger risk, not a smaller one");
   AddPos(101, POSITION_TYPE_BUY, 2.00, 1.08000, 1.07800, 1.08900);   // risk $400 = 4%
   Refresh();
   Drag(Obj(101, "S"), 1.07700);   // $600 = 6%, above the 5% cap
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0 && Has(CardStatus(), "safety cap"), "widening past the cap is blocked: " + CardStatus());
   Key(27);
   PosOf(101)->sl = 1.07600;   // the server now has $800 = 8%
   Refresh();
   Drag(Obj(101, "S"), 1.07700);   // 6%: still above the cap, but smaller
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Near(Last().sl, 1.07700), "tightening a stop above the cap goes through");
  }

static void ScenarioKeys()
  {
   Setup("Enter confirms, after the arm delay");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.07650);
   Key(13);
   EXPECT(Sent() == 0, "Enter right after the drop is ignored");
   Advance(350);
   Key(13);
   EXPECT(Sent() == 1 && Near(Last().sl, 1.07650), "Enter confirms the change");
  }

static void ScenarioTyping()
  {
   Setup("type a price on the card");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Click(Obj(101, "Sx"), YOf(1.07750));
   EXPECT(CardOpen(), "a click on the tag opens the card");
   EXPECT(Sent() == 0, "and sends nothing");
   Type(kP + "E_MSL", "1,07500");
   EXPECT(Near(PriceOf(Obj(101, "S")), 1.07500), "the SL line moves to the typed price");
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0, "Confirm right after typing is ignored");
   Key(13);
   EXPECT(Sent() == 0, "so is the Enter that ended the typing");
   Advance(600);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Near(Last().sl, 1.07500), "then it is sent");
   Advance(800);
   Click(Obj(101, "Tx"), YOf(1.08900));
   Type(kP + "E_MTP", "");
   Advance(600);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Has(CardStatus(), "Set a take profit"), "removing a required TP is refused: " + CardStatus());
   Type(kP + "E_MTP", "abc");
   EXPECT(Has(CardStatus(), "Enter a price"), "letters are refused: " + CardStatus());
   Key(27);
  }

static void ScenarioServerSide()
  {
   Setup("the trade closes while the card is open");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.07650);
   g_fake.pos.clear();
   Refresh();
   EXPECT(!CardOpen() && !Exists(Obj(101, "S")), "card and lines go");
   EXPECT(Has(PanelStatus(), "#101 is closed. Nothing was changed"), "the panel says so: " + PanelStatus());
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0, "nothing sent");

   Setup("the server's SL changes while the trader moves the TP");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "T"), 1.09100);
   Advance(350);
   PosOf(101)->sl = 1.07800;
   Refresh();
   EXPECT(Has(CardStatus(), "changed elsewhere"), "the card says the trade changed: " + CardStatus());
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0, "Confirm waits until the new values have been shown");
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Near(Last().sl, 1.07800) && Near(Last().tp, 1.09100), "the server's new SL and the trader's TP");

   Setup("part of the position is closed while the card is open");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.07650);
   PosOf(101)->volume = 0.05;
   Refresh();
   EXPECT(Has(CardStatus(), "changed elsewhere") && Has(TextOf(kP + "XMTTL#t"), "0.05"), "the card shows the new size");
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && Near(Last().sl, 1.07650), "the trader's SL is still sent");

   Setup("a pending order fills while the card is open");
   AddOrd(201, ORDER_TYPE_BUY_LIMIT, 0.10, 1.08300, 1.08100, 1.08700);
   Refresh();
   Drag(Obj(201, "E"), 1.08200);
   g_fake.ords.clear();
   AddPos(201, POSITION_TYPE_BUY, 0.10, 1.08300, 1.08100, 1.08700);
   Refresh();
   EXPECT(!CardOpen() && Has(PanelStatus(), "was filled"), "the card closes: " + PanelStatus());
   EXPECT(!Selectable(Obj(201, "E")), "the filled order's entry is now fixed");
   Advance(350);
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 0, "nothing sent");
  }

static void ScenarioFailure()
  {
   Setup("the server refuses the change");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.07650);
   Advance(350);
   g_fake.forceRetcode = TRADE_RETCODE_INVALID_STOPS;
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1 && CardOpen(), "the card stays open");
   EXPECT(Has(CardStatus(), "Not changed: Invalid SL or TP (10016)"), "and says why: " + CardStatus());
   EXPECT(Near(PriceOf(Obj(101, "S")), 1.07650), "the line stays where it was dropped");
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 1, "a second click while the request settles is ignored");
   Advance(750);
   g_fake.forceRetcode = 0;
   Click(kP + "MODOK#bg");
   EXPECT(Sent() == 2 && !CardOpen() && PosOf(101)->sl == 1.07650, "after the pause it can be sent again");
  }

static void ScenarioLocked()
  {
   Setup("stop-limit orders are locked");
   AddOrd(301, ORDER_TYPE_BUY_STOP_LIMIT, 0.10, 1.08800, 1.08500, 1.09200, ORDER_TIME_GTC, 0, 1.08700);
   Refresh();
   EXPECT(Exists(Obj(301, "E")) && !Selectable(Obj(301, "E")) && !Selectable(Obj(301, "S")) && !Selectable(Obj(301, "T")), "no line can be dragged");
   Drag(Obj(301, "S"), 1.08400);
   Click(Obj(301, "Sx"));
   EXPECT(!CardOpen() && Sent() == 0, "no card");
   EXPECT(Has(PanelStatus(), "stop-limit"), "the panel says where to change it: " + PanelStatus());
  }

static void ScenarioDrawOrder()
  {
   Setup("a new trade's lines go under the panel");
   Refresh();
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   EXPECT(OrderOf(kP + "XBG#r") > TopTradeObject(), "the panel is drawn again on top");
   Click(kP + "E_SL");   // the trader starts typing in the panel
   AddPos(102, POSITION_TYPE_SELL, 0.10, 1.09000, 1.09300, 1.08200);
   Refresh();
   EXPECT(OrderOf(kP + "XBG#r") < OrderOf(Obj(102, "S")), "not while a field is being typed in");
   Type(kP + "E_SL", "25");
   EXPECT(OrderOf(kP + "XBG#r") > TopTradeObject(), "afterwards it is");
   ObjectDelete(0, string(Obj(101, "S")));   // the Delete key removes a selected line
   Refresh();
   EXPECT(Exists(Obj(101, "S")) && OrderOf(kP + "XBG#r") > TopTradeObject(), "a deleted line comes back, under the panel");
  }

static void ScenarioDragModes()
  {
   Setup("the card opens whichever event MT5 sends first");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.07650, DRAG_POLL_ONLY);
   EXPECT(CardOpen() && Near(PriceOf(Obj(101, "S")), 1.07650), "mouse moves only");
   Key(27);
   Drag(Obj(101, "S"), 1.07600, DRAG_EVENT_ONLY);
   EXPECT(CardOpen() && Near(PriceOf(Obj(101, "S")), 1.07600), "drag event only");
   Advance(350);
   Key(13);
   EXPECT(Sent() == 1 && Near(Last().sl, 1.07600), "sent");
  }

static void ScenarioPreviewAndCard()
  {
   Setup("a new-order preview and the card at the same time");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Key('B');
   EXPECT(Shown("AINNA_L_ENTRY"), "the preview is open");
   Drag(Obj(101, "S"), 1.07650);
   Advance(350);
   Key(13);
   EXPECT(Sent() == 1 && Last().action == TRADE_ACTION_SLTP, "Enter goes to the card, not the preview");
   EXPECT(Shown("AINNA_L_ENTRY"), "the preview is still open");
   Advance(800);
   Key(13);
   EXPECT(Sent() == 2 && Last().action == TRADE_ACTION_DEAL, "with the card closed, Enter confirms the preview");
  }

static void ScenarioTimeframeChange()
  {
   Setup("a timeframe change drops an open change");
   AddPos(101, POSITION_TYPE_BUY, 0.10, 1.08000, 1.07750, 1.08900);
   Refresh();
   Drag(Obj(101, "S"), 1.07650);
   g_app.Deinit(REASON_CHARTCHANGE);
   g_app.Init();
   Refresh();
   EXPECT(!CardOpen() && Sent() == 0 && Near(PriceOf(Obj(101, "S")), 1.07750), "no card, nothing sent, lines at the server's levels");
  }

static void ScenarioTemplate()
  {
   Setup("a saved template keeps MT5's own trade lines");
   Click(kP + "PIN#bg");
   g_app.Timer();
   g_app.Timer();
   EXPECT(g_fake.templates.size() == 1 && g_fake.levelsAtSave == 1, "MT5's lines were on when the template was saved");
   EXPECT(g_fake.chartI[CHART_SHOW_TRADE_LEVELS] == 0, "and off again afterwards");
  }

//--- fuzz --------------------------------------------------------------------
static double Norm5(double p) { return std::round(p * 100000.0) / 100000.0; }

// When no change is open, every line shows what the server has, and nothing sits behind as dotted.
static std::string s_lastAction;

static void CheckLevel(ulong t, const char *level, double server, const char *what)
  {
   std::string n = Obj(t, level);
   bool ok = (server > 0.0) ? (Exists(n) && Near(PriceOf(n), server)) : !Exists(n);
   EXPECT(ok, std::string(what) + " #" + std::to_string(t) + ": server " + std::to_string(server) + ", line " +
          (Exists(n) ? std::to_string(PriceOf(n)) : std::string("none")) + " after " + s_lastAction);
  }

static void CheckLinesMatchServer()
  {
   EXPECT(GhostCount() == 0, "no dotted server-level lines while no change is open, after " + s_lastAction);
   for(auto &p : g_fake.pos)
     {
      CheckLevel(p.ticket, "E", p.open, "position entry line");
      CheckLevel(p.ticket, "S", p.sl, "position SL line");
      CheckLevel(p.ticket, "T", p.tp, "position TP line");
     }
   for(auto &o : g_fake.ords)
     {
      CheckLevel(o.ticket, "E", o.price, "order entry line");
      CheckLevel(o.ticket, "S", o.sl, "order SL line");
      CheckLevel(o.ticket, "T", o.tp, "order TP line");
     }
  }

static void Fuzz(int iterations, unsigned seed)
  {
   std::mt19937 rng(seed);
   auto R = [&](double a, double b) { return std::uniform_real_distribution<double>(a, b)(rng); };
   auto I = [&](int a, int b) { return std::uniform_int_distribution<int>(a, b)(rng); };
   for(int it = 0; it < iterations; it++)
     {
      Setup("fuzz " + std::to_string(seed) + "/" + std::to_string(it));
      g_fake.sym.stops = I(0, 1) ? 0 : I(1, 40);
      g_fake.sym.freeze = (I(0, 3) == 0) ? I(1, 30) : 0;
      g_app.cfg.maxRiskPct = (I(0, 3) == 0) ? 0.0 : R(0.5, 8.0);
      g_app.cfg.commissionRT = I(0, 1) ? 0.0 : R(0.0, 7.0);
      ulong ticket = 1000;
      auto addTrade = [&]() {
         double bid = g_fake.sym.bid, ask = g_fake.sym.ask;
         int kind = I(0, 9);
         double sl = 0.0, tp = 0.0;
         if(kind < 5)
           {
            int type = I(0, 1);
            int side = (type == POSITION_TYPE_BUY) ? 1 : -1;
            double open = Norm5(bid + R(-0.003, 0.003));
            if(I(0, 7)) sl = Norm5(open - side * R(0.0005, 0.004));
            if(I(0, 7)) tp = Norm5(open + side * R(0.0005, 0.008));
            AddPos(++ticket, type, 0.01 * I(1, 300), open, sl, tp);
            return;
           }
         int types[] = {ORDER_TYPE_BUY_LIMIT, ORDER_TYPE_BUY_STOP, ORDER_TYPE_SELL_LIMIT, ORDER_TYPE_SELL_STOP, ORDER_TYPE_BUY_STOP_LIMIT};
         int type = types[I(0, (kind == 9) ? 4 : 3)];
         bool buy = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
         bool below = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_STOP);
         double ref = buy ? ask : bid;
         double price = Norm5(below ? ref - R(0.0003, 0.004) : ref + R(0.0003, 0.004));
         int side = buy ? 1 : -1;
         if(I(0, 7)) sl = Norm5(price - side * R(0.0005, 0.004));
         if(I(0, 7)) tp = Norm5(price + side * R(0.0005, 0.008));
         int tt = I(0, 3);
         AddOrd(++ticket, type, 0.01 * I(1, 300), price, sl, tp, tt, (tt >= 2) ? g_fake.time + 86400 * I(1, 30) : 0,
                (type == ORDER_TYPE_BUY_STOP_LIMIT) ? Norm5(price - 0.0005) : 0.0);
      };
      int n = I(1, 4);
      for(int k = 0; k < n; k++)
         addTrade();
      Refresh();
      for(int step = 0; step < 80; step++)
        {
         size_t before = Sent();
         bool confirm = false;
         ulong t = 0;
         int pick = (int)(g_fake.pos.size() + g_fake.ords.size());
         if(pick > 0)
           {
            int k = I(0, pick - 1);
            t = (k < (int)g_fake.pos.size()) ? g_fake.pos[k].ticket : g_fake.ords[k - g_fake.pos.size()].ticket;
           }
         const char *levels[] = {"E", "S", "T"};
         int a = I(0, 17);
         s_lastAction = "action " + std::to_string(a) + " on #" + std::to_string(t);
         if(a <= 5 && t != 0)
           {
            std::string name = Obj(t, levels[I(0, 2)]);
            if(Exists(name))
              {
               double to = Norm5(g_fake.sym.bid + R(-0.006, 0.006));
               DragMode mode = (DragMode)I(0, 2);
               s_lastAction = "drag " + name + " to " + std::to_string(to) + " mode " + std::to_string((int)mode) + (Selectable(name) ? "" : " (locked)");
               Drag(name, to, mode);
              }
           }
         else if(a == 6 && t != 0)
            Click(Obj(t, I(0, 1) ? "Sx" : (I(0, 1) ? "Tb" : "Ex")), I(0, 700));
         else if(a == 7 || a == 8)
           {
            Click(kP + "MODOK#bg");
            confirm = true;
           }
         else if(a == 9)
            Click(kP + "MODX#bg");
         else if(a == 10)
           {
            Key(13);
            confirm = true;
           }
         else if(a == 11)
            Key(27);
         else if(a == 12 && CardOpen())
           {
            const char *fields[] = {"E_MENTRY", "E_MSL", "E_MTP"};
            std::string f = kP + fields[I(0, 2)];
            if(Exists(f) && Shown(f))
              {
               int v = I(0, 9);
               std::string text = (v == 0) ? "" : (v == 1 ? "abc" : std::to_string(Norm5(g_fake.sym.bid + R(-0.006, 0.006))));
               Type(f, text);
              }
           }
         else if(a == 13 && pick > 0)
           {
            int what = I(0, 3);
            if(what == 0 && !g_fake.pos.empty())
               g_fake.pos.erase(g_fake.pos.begin() + I(0, (int)g_fake.pos.size() - 1));
            else if(what == 1 && !g_fake.ords.empty())
               g_fake.ords.erase(g_fake.ords.begin() + I(0, (int)g_fake.ords.size() - 1));
            else if(what == 2 && !g_fake.pos.empty())
              {
               FakePos &p = g_fake.pos[I(0, (int)g_fake.pos.size() - 1)];
               int side = (p.type == POSITION_TYPE_BUY) ? 1 : -1;
               p.sl = Norm5(g_fake.sym.bid - side * R(0.0005, 0.004));
              }
            else
               addTrade();
           }
         else if(a == 14)
           {
            double spread = g_fake.sym.ask - g_fake.sym.bid;
            g_fake.sym.bid = Norm5(g_fake.sym.bid + R(-0.0008, 0.0008));
            g_fake.sym.ask = Norm5(g_fake.sym.bid + spread);
           }
         else if(a == 15)
            Advance(I(0, 1200));
         else if(a == 16)
            g_fake.forceRetcode = (I(0, 3) == 0) ? (I(0, 1) ? TRADE_RETCODE_INVALID_STOPS : 10029) : 0;
         else if(a == 17)
           {
            if(I(0, 1))
               Key(I(0, 1) ? 'B' : 'S');
            else
              {
               Click(kP + "CONFIRM#bg");
               confirm = true;
              }
           }
         Refresh();
         EXPECT(g_fake.chartI[CHART_SHOW_TRADE_LEVELS] == 0 && g_fake.chartI[CHART_DRAG_TRADE_LEVELS] == 0, "MT5's own trade lines stay off");
         EXPECT(confirm || Sent() == before, "nothing is sent without a Confirm click or key");
         EXPECT(OrderOf(kP + "XBG#r") > TopTradeObject(), "the panel stays over the trade lines");
         if(Sent() > before)
           {
            const MqlTradeRequest &r = Last();
            bool change = (r.action == TRADE_ACTION_SLTP || r.action == TRADE_ACTION_MODIFY);
            if(change && g_fake.forceRetcode == 0)
               EXPECT(!CardOpen(), "the card closes after a change goes through");
            if(change && g_fake.forceRetcode != 0)
               EXPECT(CardOpen(), "the card stays open after a refused change");
           }
         if(!CardOpen())
            CheckLinesMatchServer();
        }
     }
  }

int main(int argc, char **argv)
  {
   MqlTrapZeroDivide();
   int iterations = (argc > 1) ? atoi(argv[1]) : 300;
   unsigned seed = (argc > 2) ? (unsigned)atoi(argv[2]) : 20261021u;
   g_fake.onSend = CheckRequest;

   ScenarioChartLines();
   ScenarioLinesDrawn();
   ScenarioDragConfirm();
   ScenarioCancel();
   ScenarioTwoLevelsOneRequest();
   ScenarioOtherTradeDropsFirst();
   ScenarioPendingEntry();
   ScenarioRefusals();
   ScenarioBreakEven();
   ScenarioSafetyCap();
   ScenarioKeys();
   ScenarioTyping();
   ScenarioServerSide();
   ScenarioFailure();
   ScenarioLocked();
   ScenarioDrawOrder();
   ScenarioDragModes();
   ScenarioPreviewAndCard();
   ScenarioTimeframeChange();
   ScenarioTemplate();
   int named = s_pass + s_fail;
   int namedFail = s_fail;
   printf("app scenarios: %d checks, %d failed\n", named, namedFail);

   Fuzz(iterations, seed);
   printf("app fuzz: %d iterations x 80 steps (seed %u), %d checks, %d failed\n", iterations, seed, s_pass + s_fail - named, s_fail - namedFail);

   for(size_t i = 0; i < s_bad.size() && i < 30; i++)
      printf("BAD REQUEST %s\n", s_bad[i].c_str());
   printf("server checked %d requests: %d should never have been sent\n", s_checked, (int)s_bad.size());
   return (s_fail == 0 && s_bad.empty()) ? 0 : 1;
  }
