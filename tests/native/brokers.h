// Ways MT5 brokers differ, set up in the fake MT5 (mql.h): account type, currency, execution mode,
// filling and expiry policies, allowed order types, symbol names, requotes and slippage. The suites
// and the panel scenarios run on every profile, so a rule that holds at one broker is checked at all
// of them, against a fake server that applies that broker's rules.
#pragma once
#include "mql.h"

struct SymCase
  {
   const char *name;
   int digits;
   double point, tick, contract, tickValue, volMin, volMax, volStep;
   int stops, freeze;
   double bid, ask;
   const char *base, *profit;   // SYMBOL_CURRENCY_BASE and SYMBOL_CURRENCY_PROFIT
  };

// tickValue is in USD; a profile in another account currency converts it.
static const SymCase kSyms[] =
  {
   {"EURUSD", 5, 0.00001, 0.00001, 100000, 1.0, 0.01, 100, 0.01, 0, 0, 1.08480, 1.08500, "EUR", "USD"},
   {"USDJPY", 3, 0.001, 0.001, 100000, 0.66, 0.01, 100, 0.01, 10, 0, 151.230, 151.245, "USD", "JPY"},
   {"XAUUSDm", 3, 0.001, 0.001, 100, 0.1, 0.01, 200, 0.01, 0, 0, 2650.120, 2650.280, "XAU", "USD"},
   {"XAUUSD", 2, 0.01, 0.01, 100, 1.0, 0.01, 100, 0.01, 20, 10, 2650.12, 2650.28, "XAU", "USD"},
   {"US30", 1, 0.1, 0.1, 1, 0.1, 0.1, 500, 0.1, 0, 0, 42100.5, 42102.0, "USD", "USD"},
   {"USTEC", 2, 0.01, 0.25, 1, 0.25, 0.1, 500, 0.1, 40, 0, 18000.25, 18001.00, "USD", "USD"},
   {"BTCUSD", 2, 0.01, 0.01, 1, 0.01, 0.01, 20, 0.01, 0, 30, 67000.00, 67015.50, "BTC", "USD"},
  };
static const int kSymCount = (int)(sizeof(kSyms) / sizeof(kSyms[0]));

struct BrokerProfile
  {
   const char *name;
   int marginMode;
   bool hedgeAllowed, fifo;
   const char *currency;
   int currencyDigits;
   double fx;                    // account currency per USD
   int exeMode, filling, expiration, orderMode;
   const char *prefix, *suffix;  // around every symbol name (#XAUUSD, EURUSDm)
   bool cfdNames;                // gold is called GOLD, and symbols have no base currency
   int requotes;                 // instant and request execution: requotes before each fill
   int slipPoints;               // market and exchange execution: fills this many points worse
  };

const int kAllOrders = SYMBOL_ORDER_MARKET | SYMBOL_ORDER_LIMIT | SYMBOL_ORDER_STOP | SYMBOL_ORDER_STOP_LIMIT | SYMBOL_ORDER_SL | SYMBOL_ORDER_TP |
                       SYMBOL_ORDER_CLOSEBY;
const int kAllExpiry = SYMBOL_EXPIRATION_GTC | SYMBOL_EXPIRATION_DAY | SYMBOL_EXPIRATION_SPECIFIED | SYMBOL_EXPIRATION_SPECIFIED_DAY;
const int kFokIoc = SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC;

static const BrokerProfile kBrokers[] =
  {
   {"hedging, market execution, FOK and IOC, USD", ACCOUNT_MARGIN_MODE_RETAIL_HEDGING, true, false, "USD", 2, 1.0,
    SYMBOL_TRADE_EXECUTION_MARKET, kFokIoc, kAllExpiry, kAllOrders, "", "", false, 0, 0},
   {"suffix m, IOC only, fills 3 points worse", ACCOUNT_MARGIN_MODE_RETAIL_HEDGING, true, false, "USD", 2, 1.0,
    SYMBOL_TRADE_EXECUTION_MARKET, SYMBOL_FILLING_IOC, kAllExpiry, kAllOrders, "", "m", false, 0, 3},
   {"netting, instant execution with 2 requotes, EUR, GTC and DAY expiry", ACCOUNT_MARGIN_MODE_RETAIL_NETTING, true, false, "EUR", 2, 0.92,
    SYMBOL_TRADE_EXECUTION_INSTANT, SYMBOL_FILLING_FOK, SYMBOL_EXPIRATION_GTC | SYMBOL_EXPIRATION_DAY, kAllOrders, "", "", false, 2, 0},
   {"no opposite positions, FIFO closes, FOK only, suffix .r", ACCOUNT_MARGIN_MODE_RETAIL_HEDGING, false, true, "USD", 2, 1.0,
    SYMBOL_TRADE_EXECUTION_MARKET, SYMBOL_FILLING_FOK, SYMBOL_EXPIRATION_GTC, kAllOrders, "", ".r", false, 0, 0},
   {"exchange execution and margin, JPY, prefix #, DAY or dated expiry", ACCOUNT_MARGIN_MODE_EXCHANGE, true, false, "JPY", 0, 150.0,
    SYMBOL_TRADE_EXECUTION_EXCHANGE, kFokIoc, SYMBOL_EXPIRATION_DAY | SYMBOL_EXPIRATION_SPECIFIED,
    SYMBOL_ORDER_MARKET | SYMBOL_ORDER_LIMIT | SYMBOL_ORDER_STOP | SYMBOL_ORDER_SL | SYMBOL_ORDER_TP, "#", "", false, 0, 2},
   {"request execution with a requote, cent account, no filling flags, suffix .pro", ACCOUNT_MARGIN_MODE_RETAIL_HEDGING, true, false, "USC", 2,
    100.0, SYMBOL_TRADE_EXECUTION_REQUEST, 0, SYMBOL_EXPIRATION_GTC, kAllOrders, "", ".pro", false, 1, 0},
   {"dated expiry only, no stop orders, FOK only", ACCOUNT_MARGIN_MODE_RETAIL_HEDGING, true, false, "USD", 2, 1.0,
    SYMBOL_TRADE_EXECUTION_MARKET, SYMBOL_FILLING_FOK, SYMBOL_EXPIRATION_SPECIFIED,
    SYMBOL_ORDER_MARKET | SYMBOL_ORDER_LIMIT | SYMBOL_ORDER_SL | SYMBOL_ORDER_TP, "", "", false, 0, 0},
   {"no SL or TP on the symbol, netting, exchange execution", ACCOUNT_MARGIN_MODE_RETAIL_NETTING, true, false, "USD", 2, 1.0,
    SYMBOL_TRADE_EXECUTION_EXCHANGE, kFokIoc, kAllExpiry, SYMBOL_ORDER_MARKET | SYMBOL_ORDER_LIMIT | SYMBOL_ORDER_STOP, "", "", false, 0, 0},
   {"CFD names: GOLD, no base currency, suffix .c", ACCOUNT_MARGIN_MODE_RETAIL_HEDGING, true, false, "USD", 2, 1.0,
    SYMBOL_TRADE_EXECUTION_MARKET, kFokIoc, kAllExpiry, kAllOrders, "", ".c", true, 0, 1},
  };
static const int kBrokerCount = (int)(sizeof(kBrokers) / sizeof(kBrokers[0]));

// A fresh fake terminal with one symbol, as the broker of the default profile has it.
inline void SetUpSymbol(const SymCase &c)
  {
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
   g_fake.sym.base = c.base;
   g_fake.sym.profit = c.profit;
   _Symbol = string(c.name);
  }

// The account and the symbol as this broker has them. Call after SetUpSymbol (or g_fake.Reset).
inline void ApplyBroker(const BrokerProfile &b)
  {
   g_fake.marginMode = b.marginMode;
   g_fake.hedgeAllowed = b.hedgeAllowed;
   g_fake.fifo = b.fifo;
   g_fake.currency = b.currency;
   g_fake.currencyDigits = b.currencyDigits;
   g_fake.balance = 10000.0 * b.fx;
   g_fake.equity = 10000.0 * b.fx;
   g_fake.marginFree = 10000.0 * b.fx;
   FakeSym &s = g_fake.sym;
   s.tickValue *= b.fx;
   s.exeMode = b.exeMode;
   s.filling = b.filling;
   s.expiration = b.expiration;
   s.orderMode = b.orderMode;
   std::string core = s.name;
   if(b.cfdNames)
     {
      if(s.base == "XAU")
         core = "GOLD";
      s.base = "";
      s.profit = "";
     }
   s.name = std::string(b.prefix) + core + b.suffix;
   g_fake.requotes = b.requotes;
   g_fake.requotesLeft = b.requotes;
   g_fake.slip = b.slipPoints * s.point;
   _Symbol = string(s.name);
  }

inline bool BrokerHedging(const BrokerProfile &b) { return b.marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; }
