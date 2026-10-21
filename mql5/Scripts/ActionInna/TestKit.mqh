//+------------------------------------------------------------------+
//| ActionInna tests - counters, reporting and seeded random numbers |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_TESTKIT_MQH
#define ACTIONINNA_TESTKIT_MQH

#include <ActionInna\RiskCalc.mqh>
#include <ActionInna\Memory.mqh>
#include <ActionInna\Hotkeys.mqh>
#include <ActionInna\OrderLines.mqh>

#define TK_MAX_DETAILS 50

int    g_pass = 0;
int    g_fail = 0;
int    g_shown = 0;
string g_report = "";
string g_table = "";
uint   g_rng = 1;

// Example test, reported by its name.
void Check(const bool cond, const string name)
  {
   if(cond)
     {
      g_pass++;
      return;
     }
   g_fail++;
   if(g_shown < TK_MAX_DETAILS)
     {
      g_shown++;
      g_report += "FAIL: " + name + "\r\n";
      Print("FAIL: ", name);
     }
  }

// Scenario check: counts the case. The caller builds the failure details only when it fails.
bool Expect(const bool cond, int &fails)
  {
   if(cond)
     {
      g_pass++;
      return true;
     }
   g_fail++;
   fails++;
   return false;
  }

void Detail(const string suite, const string detail)
  {
   if(g_shown >= TK_MAX_DETAILS)
      return;
   g_shown++;
   g_report += "FAIL " + suite + ": " + detail + "\r\n";
   Print("FAIL ", suite, ": ", detail);
  }

void Row(const string suite, const int cases, const int fails)
  {
   g_table += suite + ": " + IntegerToString(cases) + " cases, " +
              ((fails == 0) ? "all passed" : IntegerToString(fails) + " FAILED") + "\r\n";
  }

bool Near(const double a, const double b, const double eps = 1e-9)
  {
   return MathAbs(a - b) <= eps;
  }

// A number for failure details, with its trailing zeros cut.
string D(const double v)
  {
   return AiTrimZeros(DoubleToString(v, 10));
  }

// xorshift32. The same seed produces the same scenarios, so a failure can be replayed exactly.
uint RndU()
  {
   g_rng ^= (g_rng << 13);
   g_rng ^= (g_rng >> 17);
   g_rng ^= (g_rng << 5);
   return g_rng;
  }

double Rnd01()
  {
   return (double)(RndU() & 0xFFFFFF) / 16777216.0;
  }

int RndInt(const int lo, const int hi)
  {
   return lo + (int)(RndU() % (uint)(hi - lo + 1));
  }

double RndRange(const double lo, const double hi)
  {
   return lo + (hi - lo) * Rnd01();
  }

// True about once in 'oneIn' calls.
bool RndChance(const int oneIn)
  {
   return RndInt(1, oneIn) == 1;
  }

// A made-up but legal symbol: 0 to 5 digits, ticks of 1, 5, 10 or 25 points, volume steps from
// 0.001 to 1 lot, a minimum that is a whole number of steps, any stops level, any pip convention.
void RandomSpec(AiSpec &s)
  {
   ZeroMemory(s);
   s.symbol = "TEST";
   s.digits = RndInt(0, 5);
   s.point = MathPow(10.0, -s.digits);
   int tickPoints = 1;
   int pick = RndInt(0, 5);
   if(pick == 0)
      tickPoints = 5;
   else if(pick == 1)
      tickPoints = 25;
   else if(pick == 2)
      tickPoints = 10;
   s.tickSize = s.point * tickPoints;
   double steps[4] = {0.001, 0.01, 0.1, 1.0};
   s.volStep = steps[RndInt(0, 3)];
   s.volMin = s.volStep * RndInt(1, 10);
   s.volMax = s.volMin * RndInt(10, 5000);
   s.volDigits = AiStepDigits(s.volStep);
   s.stopsLevel = RndChance(3) ? 0 : RndInt(1, 200);
   s.pipSize = AiPipSize("TEST", s.digits, s.point, RndInt(0, 2));
   s.pipPoints = AiSafeDiv(s.pipSize, s.point, 1.0);
   s.ok = true;
  }

#endif
