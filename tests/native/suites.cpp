// Runs ActionInnaTests (worked examples and every generated suite) natively, for several seeds and
// several made-up symbols. Then runs the suites that read the terminal (order plans and changes to
// open trades) at every broker profile in brokers.h, with and without positions open. Exits with 1
// when any check fails.
//   suites [seeds] [rounds]
#include "mql.h"
#include "brokers.h"
#include "out/src/Scripts/ActionInna/ActionInnaTests.mq5"

static void ResetCounters()
  {
   g_pass = 0;
   g_fail = 0;
   g_shown = 0;
   g_report = string();
   g_table = string();
  }

// Positions already open on the symbol: one, or on a hedging account sometimes one each way.
static void AddOpenTrades(int k)
  {
   const FakeSym &s = g_fake.sym;
   int64_t t = (int64_t)g_fake.time * 1000;
   int type = (k % 2) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   g_fake.pos.push_back(FakePos{500001, type, s.volMin, s.bid, 0.0, 0.0, 0.0, t - 60000, s.name});
   if(g_fake.marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && k % 3 == 0)
      g_fake.pos.push_back(FakePos{500002, 1 - type, s.volMin, s.ask, 0.0, 0.0, 0.0, t - 30000, s.name});
  }

int main(int argc, char **argv)
  {
   MqlTrapZeroDivide();
   int seeds = (argc > 1) ? atoi(argv[1]) : 3;
   int rounds = (argc > 2) ? atoi(argv[2]) : 1;
   int failed = 0;
   int64_t checks = 0;
   for(int k = 0; k < seeds; k++)
      for(int j = 0; j < kSymCount; j++)
        {
         const SymCase &c = kSyms[j];
         SetUpSymbol(c);
         ResetCounters();
         InpSeed = 20261021u + 7919u * (uint)(k * kSymCount + j);
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
   printf("\nsuites: %s checks over %d seeds x %d symbols, %d failed\n\n", std::to_string(checks).c_str(), seeds, kSymCount, failed);

   int64_t brokerChecks = 0;
   int brokerFailed = 0;
   for(int b = 0; b < kBrokerCount; b++)
     {
      int profileChecks = 0;
      int profileFailed = 0;
      for(int j = 0; j < kSymCount; j++)
        {
         SetUpSymbol(kSyms[j]);
         ApplyBroker(kBrokers[b]);
         if((b + j) % 2 == 1)
            AddOpenTrades(b + j);
         ResetCounters();
         g_rng = 20261021u + 104729u * (uint)(b * kSymCount + j);
         SuiteLivePlans(1000 * rounds);
         SuiteLiveModify(1000 * rounds);
         SuiteMoney(500 * rounds);
         // Every broker's name for a symbol gets the same Trader pip: gold 0.1, 3- and 5-digit
         // symbols 10 points, others 1 point.
         const SymCase &c = kSyms[j];
         AiSpec s;
         AiLoadSpec(_Symbol, AI_PIP_TRADER, s);
         double pip = (std::string(c.base) == "XAU") ? 0.1 : ((c.digits == 3 || c.digits == 5) ? c.point * 10.0 : c.point);
         Check(Near(s.pipSize, pip, 1e-12), "Trader pip " + D(s.pipSize) + " on " + _Symbol + ", expected " + D(pip));
         profileChecks += g_pass + g_fail;
         if(g_fail > 0)
           {
            printf("FAILED at %s, %s:\n%s%s\n", kBrokers[b].name, _Symbol.s.c_str(), g_table.s.c_str(), g_report.s.c_str());
            profileFailed += g_fail;
           }
        }
      printf("broker %-78s %7d checks, %d failed\n", kBrokers[b].name, profileChecks, profileFailed);
      brokerChecks += profileChecks;
      brokerFailed += profileFailed;
     }
   printf("\nbrokers: %s checks over %d profiles x %d symbols, %d failed\n", std::to_string(brokerChecks).c_str(), kBrokerCount, kSymCount,
          brokerFailed);
   return (failed + brokerFailed) ? 1 : 0;
  }
