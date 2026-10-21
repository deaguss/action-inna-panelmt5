// Runs ActionInnaTests (worked examples and every generated suite) natively, for several seeds and
// several made-up symbols, and exits with 1 when any check fails.
//   suites [seeds] [rounds]
#include "mql.h"
#include "out/src/Scripts/ActionInna/ActionInnaTests.mq5"

struct SymCase
  {
   const char *name;
   int digits;
   double point, tick, contract, tickValue, volMin, volMax, volStep;
   int stops, freeze;
   double bid, ask;
  };

static const SymCase kSyms[] =
  {
   {"EURUSD", 5, 0.00001, 0.00001, 100000, 1.0, 0.01, 100, 0.01, 0, 0, 1.08480, 1.08500},
   {"USDJPY", 3, 0.001, 0.001, 100000, 0.66, 0.01, 100, 0.01, 10, 0, 151.230, 151.245},
   {"XAUUSDm", 3, 0.001, 0.001, 100, 0.1, 0.01, 200, 0.01, 0, 0, 2650.120, 2650.280},
   {"XAUUSD", 2, 0.01, 0.01, 100, 1.0, 0.01, 100, 0.01, 20, 10, 2650.12, 2650.28},
   {"US30", 1, 0.1, 0.1, 1, 0.1, 0.1, 500, 0.1, 0, 0, 42100.5, 42102.0},
   {"USTEC", 2, 0.01, 0.25, 1, 0.25, 0.1, 500, 0.1, 40, 0, 18000.25, 18001.00},
   {"BTCUSD", 2, 0.01, 0.01, 1, 0.01, 0.01, 20, 0.01, 0, 30, 67000.00, 67015.50},
  };

int main(int argc, char **argv)
  {
   MqlTrapZeroDivide();
   int seeds = (argc > 1) ? atoi(argv[1]) : 3;
   int rounds = (argc > 2) ? atoi(argv[2]) : 1;
   int nsym = (int)(sizeof(kSyms) / sizeof(kSyms[0]));
   int failed = 0;
   int64_t checks = 0;
   for(int k = 0; k < seeds; k++)
      for(int j = 0; j < nsym; j++)
        {
         const SymCase &c = kSyms[j];
         g_fake.Reset();
         g_fake.sym.name = c.name;
         g_fake.sym.digits = c.digits;
         g_fake.sym.point = c.point;
         g_fake.sym.tickSize = c.tick;
         g_fake.sym.contract = c.contract;
         g_fake.sym.tickValue = c.tickValue;
         g_fake.sym.volMin = c.volMin;
         g_fake.sym.volMax = c.volMax;
         g_fake.sym.volStep = c.volStep;
         g_fake.sym.stops = c.stops;
         g_fake.sym.freeze = c.freeze;
         g_fake.sym.bid = c.bid;
         g_fake.sym.ask = c.ask;
         _Symbol = string(c.name);
         g_pass = 0;
         g_fail = 0;
         g_shown = 0;
         g_report = string();
         g_table = string();
         InpSeed = 20261021u + 7919u * (uint)(k * nsym + j);
         InpRounds = rounds;
         OnStart();
         checks += g_pass + g_fail;
         printf("seed %10u  %-8s %8d checks, %d failed\n", InpSeed, c.name, g_pass + g_fail, g_fail);
         if(k == 0 && j == 0)
            printf("%s", g_table.s.c_str());
         if(g_fail > 0)
           {
            printf("%s%s\n", g_table.s.c_str(), g_report.s.c_str());
            failed += g_fail;
           }
        }
   printf("\nsuites: %s checks over %d seeds x %d symbols, %d failed\n", std::to_string(checks).c_str(), seeds, nsym, failed);
   return failed ? 1 : 0;
  }
