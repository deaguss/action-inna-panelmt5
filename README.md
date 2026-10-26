# ActionInna

[![checks](https://github.com/deaguss/action-inna-panelmt5/actions/workflows/checks.yml/badge.svg)](https://github.com/deaguss/action-inna-panelmt5/actions/workflows/checks.yml)
[![licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

A risk trade panel for **MetaTrader 5 desktop**, modelled on the order form of the Exness web terminal. It
sits on the chart in place of MT5's One-Click panel:

- **Risk presets** 1% / 1.5% / 2% plus a custom value (in %, money or fixed lots). The lot size is worked
  out for you.
- **Stop loss in pips or price, take profit in pips, price or R** (a multiple of the stop distance).
- **Preview before anything is sent**: entry, SL and TP lines on the chart with their price, pips, money
  and %. Drag the lines and every number follows. The order goes out only when you press Confirm.
- **Market and pending orders**. Drag the entry line away from the price and it becomes a Limit or
  Stop order.
- **Change open trades with a confirm pop-up**, as on Exness. Drag the SL, TP or entry line of an open
  position or pending order and a card shows the new prices and money. Nothing changes until you press
  Confirm. (With MT5's own trade lines, a drag can change the order the moment you let go.)
- **Slippage handled the way you set the stop**: when a market order fills at another price, an SL in
  pips (and a TP in pips or R) moves with the fill, so the money at risk stays as planned. A level set
  as a price stays, and the panel says what the stop now risks.
- **Recall of earlier SL/TP** per symbol, like Exness's "Set SL/TP automatically".
- **Hotkeys** for the presets, buy/sell preview, confirm and cancel.
- **Stays put**: MT5 reopens it with your charts. "Pin to new charts" puts it on every new chart too.

It is an Expert Advisor (MQL5), so it runs inside MT5 with MT5's own prices and order execution.

**What has been tested so far:**

- It compiles with 0 errors and 0 warnings in MetaEditor (MT5 desktop for Windows).
- Tried by hand in MT5 desktop:
  - a pending SELL STOP was placed through the panel, with its SL and TP;
  - Pin to new charts works, and so does reopening MT5 with the panel back on its charts;
  - the risk numbers on the panel match a hand calculation;
  - an open position's SL and TP were changed by dragging their lines and confirming on the card.
- Without MT5, the native tests (section 11) run the panel's checks and orders against nine broker
  set-ups in a fake MT5 whose server applies each set-up's rules: hedging and netting accounts,
  accounts without opposite positions or with first-in-first-out closes, market, instant, request and
  exchange execution, limited filling and expiry modes, symbols that take no stop orders or no SL/TP,
  symbol names with prefixes and suffixes, and USD, EUR, JPY and cent accounts.
- The browser panel (section 4) has been tested without MT5 only: the EA's side natively (every
  request at every broker set-up, the pipe and its key), the link against made-up EAs, and the side
  panel in a browser tab against a stand-in for the link and MT5. In MT5 only its named pipe has run,
  with a test EA: a round trip from the browser to MT5 and back took 31 ms (median), 62 ms at most.
- Not yet tried: market orders through the panel, dragging a pending order's entry, the rest of the
  checklist in section 10, real brokers other than Exness, and MT5 on Mac or Linux. If you run it
  there, open an issue with what you saw.

The test script and how to run it are in section 10.

---

## 1. Install

### This PC (development set-up)

In PowerShell, from this folder:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\link-mt5.ps1
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Tests
```

- `link-mt5.ps1` links the sources into your MT5 data folder (it asks which terminal when there is more
  than one). It also keeps a copy of your default chart template, named `default-before-ActionInna`.
- `build.ps1` compiles with MetaEditor. The compile logs land in `build\`.

Then in MT5: **Navigator > right-click > Refresh**. ActionInna appears under **Expert Advisors**.

### Another PC (just use it)

Copy `ActionInna.ex5` into `<data folder>\MQL5\Experts\` (MT5: **File > Open Data Folder**), then
**Navigator > Refresh**. Nothing else is needed.

## 2. First run

1. Switch on **Algo Trading** in the MT5 toolbar.
2. Drag **ActionInna** onto a chart. In the **Common** tab, tick **Allow Algo Trading**. Check the
   **Inputs** tab (section 8), then press OK.
3. Use a chart without another EA on it: MT5 allows one EA per chart.

Try it on your **demo account** first (section 10 has a checklist).

## 3. Keep it on the desktop (pinning)

- **Every start of MT5.** MT5 saves your open charts, with their EAs, when it closes, and reopens them
  at the next start. Attach ActionInna once and it is there next time. Close MT5 normally so it can save.
- **Every new chart.** Open the panel's menu (`...`) and choose **Pin to new charts**. ActionInna saves
  the current chart, with the EA on it, as MT5's default template, and every chart you open after that
  loads the panel. To undo it, open a chart, apply the template `default-before-ActionInna`
  (right-click > Templates), and save it as `default`.
- **Some charts only.** Choose **Save template** in the same menu, then apply `ActionInna-panel` to any
  chart with right-click > Templates.
- Tip: in the Navigator, right-click ActionInna > **Add to Favorites**.

## 4. Using the panel

1. **Pick the risk.** Choose 1%, 1.5% or 2%, or type a custom value. The button next to the custom
   field switches its unit between %, money and lots.
2. **Set the stop loss** in pips. Press the `pips` button to type a price instead.
3. **Set the take profit**: `R` (2 means twice the stop distance), `pips` or `price`.
4. Press **BUY** or **SELL**. The preview appears on the chart. Drag the SL, TP or entry line, or edit
   the fields; the lot size and every amount follow.
5. Press **Confirm BUY 0.40 lots**. **X** or **Esc** closes the preview, and nothing is sent.

Dragging a line switches that field to `price`, so the level stays where you dropped it. Press the mode
button to go back to pips; the line keeps its place.

**Pending orders.** Press **Market** to switch to **Pending**, or simply drag the entry line. The type
follows from the price:

| Side | Entry below the market | Entry above the market |
|---|---|---|
| Buy | Buy Limit | Buy Stop |
| Sell | Sell Stop | Sell Limit |

**Recall of earlier SL/TP.**

- **Set SL/TP automatically** is on by default; turn it on or off in the `...` menu. When you open a
  preview, it fills in the SL and TP you used last time on this symbol, in the mode you used:
  - pips stay pips, and R stays R;
  - a price level stays a price if it still sits on the right side of the entry; otherwise the same
    distance is used.
- **Last** (next to SL and TP) and the **R** key step back through up to 10 earlier choices.
- The history is saved after every order that goes through, in `Terminal\Common\Files\ActionInna\recall`,
  so every MT5 terminal on this PC shares it. Distances are saved as price (a $5 gold stop is 5.0), so
  they mean the same at a broker that quotes the symbol with more or fewer digits.
- Before anything is saved, recall uses the SL/TP of your newest open position or recent trade on the
  symbol.

**Changing open trades (drag, then confirm).**

When One-Click Trading is on, MT5's own trade lines change a position or order the moment a drag
ends. ActionInna switches those lines off on its chart and draws its own for every position and
pending order on the symbol. Dragging one of them never sends anything:

- Drag a **SL** or **TP** line, or a pending order's **entry** line. The tag on the line shows the new
  price and money while you drag.
- Let go and the modify card opens beside the panel. It shows each level's new price, the old one
  ("was ..."), the money and % at each level, and the risk : reward. You can also type the prices in its
  fields.
- **Confirm change** sends the change. **Cancel** (or **Esc**) puts the lines back, and nothing is sent.
- Moving a pending order's entry moves its SL and TP along with it, so the money at risk stays the
  same. Drag SL or TP afterwards to set them on their own.
- A position's stop may go to break-even or past it, to lock in profit. The card checks the levels
  against the market price, the broker's minimum distance and its freeze level, and against "Require a
  stop loss / take profit".
- The safety cap blocks a change that raises the risk above it. Tightening a stop is never blocked.
- Click a trade's tag to open the card without dragging, for example to add a missing SL or TP.
- Stop-limit orders are drawn but locked: change them in MT5's Trade tab.
- Drag another line of the same trade before confirming, and the card shows both changes and sends
  them in one request. Dragging a different trade drops the first change.

Switch this off with the input **Drag open trades with a confirm pop-up**. MT5's own lines come back
when it is off and when the EA is removed. Charts without ActionInna keep MT5's own behaviour.

**Other.**

- **Collapse**: the `-` button or **H** shrinks the panel to a slim SELL / risk / BUY bar. Its middle
  button steps through the risk choices (1%, 1.5%, 2%, custom). During a preview the bar also shows
  CONFIRM. A chart too short for the full panel always gets the slim bar, so CONFIRM never falls off
  the chart.
- **Move**: drag the panel by its header. Drop it near the right edge and it docks there. While docked,
  ActionInna shifts the chart so the panel does not cover the last candles.
- **One-click trading** (`...` menu, off by default) sends at once on SELL/BUY, with no preview. It asks
  before switching on, and goes back off when MT5 restarts.

What the panel shows:

| Row | Meaning |
|---|---|
| Lots | Lot size (and units) |
| Risk | Money lost if the stop is hit, commission included, and % of equity |
| Reward | Money won at the target, commission deducted |
| Risk : reward | Target distance divided by stop distance |
| Distance (pips) | SL and TP distance from the entry |
| Pip value | Money per pip at this lot size |
| Margin | Margin the order needs, and the free margin left after it |

### In the browser (in development)

A side panel for Chrome (also Edge and Brave), next to TradingView, with the same numbers and checks.
Everything it shows comes from the ActionInna EA in MT5, and everything it sends goes through it:

- **The order form** is the chart panel's: SELL/BUY, Market or Pending, risk 1 / 1.5 / 2 % or your
  own (%, money or lots), SL in pips or price, TP in R, pips or price, Last, the numbers, Confirm.
- **The symbol:** type it, or a TradingView ticker such as `OANDA:XAUUSD`. ActionInna finds the
  broker's name for it (`XAUUSDm`, `#XAUUSD`, `GOLD`) and asks when more than one fits. **Follow
  TradingView's symbol** asks for access to TradingView's tabs, and reads only their address and
  title.
- **Open trades:** every position and pending order on every symbol, with its profit. Close (all or
  part), Change SL/TP (a pending order's entry too) and Remove each open a card with the money at the
  new levels. Nothing changes until its Confirm.
- **Several MT5s** (two brokers, say): a list picks the one the panel works with.
- **Confirm waits for MT5.** It stays off until MT5's numbers for what you typed are in, and while
  MT5 hasn't been heard from for 3 seconds. If MT5's answer to an order is lost on the way (the link
  or MT5 stopped), the panel doesn't say "not sent": it says the order may have gone through, and to
  check Open trades before sending again.
- **One ActionInna chart in each MT5 serves the browser panel.** It doesn't matter which: if that
  chart closes, another ActionInna chart takes over within seconds. The input **Serve the browser
  side panel** switches this off.
- **MT5 needs no setting for it.** The EA talks to a small program on this PC (the *link*) through a
  named pipe. Only your Windows user can open the pipe, and the EA serves the link only after it
  sends a key that only your Windows user can read.
- **The same checks as on the chart.** Every order, change or close from the browser is previewed
  first, and checked again with fresh prices when it is confirmed.
- **MT5 starts by itself.** When the panel opens and no MT5 is connected, the link starts the MT5s
  you installed it for, minimised.

Neither the side panel nor the link is released yet: for now the panel is loaded unpacked, and the
link built from this repository (section 11). How the pieces talk is in
[docs/protocol.md](docs/protocol.md).

## 5. Hotkeys

The chart must have focus (click it once).

| Key | Action |
|---|---|
| **B** / **S** | Preview buy / sell (press again to close) |
| **1** / **2** / **3** | Risk presets |
| **4** | Custom risk |
| **Enter** | Confirm the previewed order |
| **Esc** | Close the preview |
| **R** | Recall earlier SL/TP (press again for older ones) |
| **P** | Switch Market / Pending |
| **H** | Collapse / expand |
| **Tab** / **Shift+Tab** | Move through every control on the panel, with a focus ring around the current one |
| **Enter** / **Space** | Press the control with the focus ring (Esc leaves the panel) |

Every key in the first part of the table can be changed in the inputs, for example `SHIFT+B`, `F5` or
`CTRL+1`; leave a key empty to switch it off. Alt combinations are not offered because MT5 keeps them.
Tab works even with the hotkeys switched off. Typing a number into a field (custom risk, SL, TP, entry)
needs a click on the field: MT5 has no way for a program to put the cursor in a field.

While the modify card is open, the Confirm key (Enter) confirms the change and the Cancel key (Esc)
discards it. Once the card is closed, they work on the preview again.

While ActionInna runs, Enter and Space no longer open MT5's quick-navigation box. It comes back when the
EA is removed.

Safeguards:
- A held key does not repeat.
- The Enter that finishes typing in a field does not confirm the order.
- Clicks and keys pressed while an order is being sent are ignored.

## 6. How the numbers are worked out

- **Risk money** = risk % × equity (or balance: `...` menu or the input), or the amount you typed.
- **Loss per lot** = what MT5 itself calculates (`OrderCalcProfit`) for 1 lot from the entry to the stop,
  in your account currency, plus the commission per lot from the inputs. This covers cross pairs, gold and
  indices.
- **Lots** = risk money ÷ loss per lot, **rounded down** to the symbol's volume step. The actual risk is
  never above your target, and the panel shows the actual figure.
- **Entry**: a buy opens at the Ask and a sell at the Bid. A buy's stop triggers on the Bid, so the spread
  is part of the risk.
- Example: EURUSD, $10,000 equity, 1%, SL 25 pips: $100 ÷ $250 per lot = **0.40 lots**. TP 2R = 50 pips
  = **+$200**.

CONFIRM stays disabled, and the status line says why, when any of these holds:
- even the minimum lot would risk more than your target;
- the risk is above the safety cap (5% by default);
- SL or TP is missing (both are required by default);
- SL or TP is closer to the price than the broker allows;
- there is not enough free margin;
- the symbol does not allow that kind of order.

**Pip conventions** (input "Pip convention"):

| Convention | EURUSD | USDJPY | XAUUSD | A $5 move on gold |
|---|---|---|---|---|
| Trader (default) | 0.0001 | 0.01 | 0.1 | 50 pips |
| 10 points (1 pip = 10 points everywhere, as Exness counts) | 0.0001 | 0.01 | 0.01 | 500 pips |
| Points | 1 point | 1 point | 1 point | 5,000 points (3-digit gold) |

The lot size and money do not depend on the convention, only the pip numbers do.

### Slippage

A market order fills at the price the broker has when the order arrives, which can differ from the
price in the preview. Most accounts use market execution, where MT5 ignores the "Max slippage"
input. On instant and request execution a price that moved too far comes back as a requote, and
ActionInna tries again at the new price, up to three times. In every mode it refuses to send an order
whose risk grew more than 5% since the preview.

The order always goes out with its SL and TP. When it fills a tick or more away from the planned
entry, the input "When a market order fills at another price" decides what happens next:

| Choice | SL | TP | Money at risk |
|---|---|---|---|
| Follow the SL mode (default) | In pips: moves with the fill. As a price: stays | In pips: moves with the fill. In R: R stop distances from the fill. As a price: stays | As planned with an SL in pips, otherwise changed by the slippage |
| Keep SL and TP where they were set | Stays | Stays | Changed by the slippage |
| Move SL and TP with the fill | Moves | Moves | As planned |

Moving a level is a second request, checked like any change to an open trade (stops and freeze
levels). If it can't be sent, the order keeps the SL and TP it was sent with. The status line says
what happened, for example:

- `Filled 3.0 pips worse. SL/TP moved: risk $100.00 as planned`
- `Filled 3.0 pips worse. SL kept, TP moved: risk $115.00 (plan $100.00)`

Example: EURUSD, $10,000 equity, 1% with a 20-pip stop is 0.50 lots and $100. The BUY fills 3 pips
above the preview's ask:

- With the SL in pips, it moves up 3 pips and still risks $100.
- With the SL set as a price, it stays, so the stop is now 23 pips away and risks $115.

Other cases:

- On a netting account, an order that joins an open position leaves that position's SL/TP alone.
- Pending orders aren't touched: a limit fills at its price or better, and a stop fills at the next
  price with the SL and TP it was given.

### Other brokers

ActionInna reads from MT5, at run time, everything that differs between brokers:
- the symbol: digits, tick size, lot limits and step, stops and freeze levels
- what the symbol allows: order types, filling modes, expiry types, SL and TP
- how MT5 executes it: market, instant, request or exchange
- the account: hedging or netting, whether opposite positions are allowed, the decimals of its currency

What that means in practice:

- **Symbol names.** Gold counts as gold under any name with XAU or GOLD in it (`#XAUUSD`, `XAUUSD.r`,
  `GOLDm`), or when its base currency is XAU.
- **Netting accounts.** An order merges with the symbol's open position. The panel warns before you
  confirm.
- **Accounts without opposite positions** (common under US rules). An order against an open position
  is refused on the panel, with the reason, before it reaches the broker.
- **Currencies.** Money shows with the account currency's decimals: `$1,234.50`, `1,235 JPY`.

## 7. Working alongside other EAs and trade guards

- Every order carries **both SL and TP in the same request**, so a position is never open without
  them, not even for a moment. Tools that close positions missing a stop or target never catch one.
- With magic number 0 (the default), ActionInna's trades count as **manual trades**: anything that
  manages or guards your manual trading treats them as yours.
- ActionInna does not know other tools' rules. A guard that closes trades above a position limit, or
  while it has locked the account, still closes ActionInna's trades.

## 8. Inputs

| Group | Input | Default |
|---|---|---|
| Risk | Risk presets 1-3 | 1, 1.5, 2 (%) |
| | Risk % is measured on | Equity |
| | Safety cap | 5% |
| | Commission per lot, round turn | 0 (set it for Raw Spread / Zero accounts, e.g. 7 on Raw Spread) |
| SL / TP | Require a stop loss / take profit | on / on |
| | Default stop loss | 20 pips |
| | Default take profit | 2 R |
| | Pip convention | Trader |
| | Set SL/TP automatically | on |
| | New pending order distance | 10 pips |
| Execution | One-click trading | off |
| | Magic number | 0 (manual trade) |
| | Max slippage | 10 points (instant and request execution only) |
| | When a market order fills at another price | Follow the SL mode (section 6, Slippage) |
| | Order comment | ActionInna |
| | Drag open trades with a confirm pop-up | on (replaces MT5's own trade lines on this chart) |
| Hotkeys | Keys, see section 5 | |
| Display | Hide MT5's One-Click panel | on |
| | Shift the chart for the panel | on |
| | Shade the risk / reward zones | on |
| | Theme | Auto (follows the chart background) |
| | Panel scale | 1.0 (follows the Windows display scale) |
| | Font / size | Arial 9 (on every Windows PC, so the text keeps the sizes the layout was measured for) |
| | Sounds | on |
| | Log file | on: `MQL5\Files\ActionInna\log.txt` |
| Browser panel | Serve the browser side panel | on (one chart per MT5 does it; section 4) |

Panel choices (risk chip, custom values, toggles, position) are saved in
`Terminal\Common\Files\ActionInna\settings.txt`. An input you change wins over the saved panel choice.

## 9. Troubleshooting

| Message or symptom | What to do |
|---|---|
| Turn on Algo Trading | Toolbar button **Algo Trading** |
| Tick 'Allow Algo Trading' | EA properties (F7 on the chart) > Common |
| Not sent: Unsupported filling mode | ActionInna already tries every allowed mode. Send the log. |
| Not sent: Market is closed | The symbol's trading session is closed |
| Not sent: Invalid SL or TP / too close | Move the line further away: the broker has a minimum distance |
| Min lot would risk ... | The stop is too wide for the risk; tighten it, raise the risk, or use lots |
| Panel too small or too large | Input **Panel scale** |
| One-Click panel missing after MT5 crashed | Right-click the chart > One Click Trading (Alt+T) |
| MT5's own trade lines are gone from the chart | ActionInna draws its own while it runs (section 4). They come back when the EA is removed. After a crash: F8 > Show > Show trade levels |
| Too close to the market to change (freeze level) | The broker freezes a level or order this close to the price. Wait for the price to move away |
| This account allows no opposite positions | Close the opposite position on this symbol first |
| Filled ... pips worse. SL/TP not moved | The slippage move could not be sent (often the freeze level). The order kept the SL and TP it was sent with; the log says why |
| Anything else | The log: `MQL5\Files\ActionInna\log.txt` (with the dev set-up: `runtime\log.txt` here) |

## 10. Test checklist (demo account first)

1. Run the **ActionInnaTests** script (Navigator > Scripts > ActionInna, drag it onto any chart, press
   OK). It runs the worked examples, then about 124,000 generated scenarios: lot sizing, rounding,
   order types, SL/TP checks and changes to open trades against independent references, entry moves,
   SL/TP after slippage,
   recall files (including damaged ones), typed numbers, hotkey names, pip sizes, money formatting,
   and 2,000 full order plans plus 2,000 changes to open trades on the chart's symbol with live
   prices. It sends no orders. Every suite should say "all passed". Raise **Rounds**
   for more scenarios, and change **Seed** for different ones (the same seed replays the same ones).
   The report goes to `MQL5\Files\ActionInna\test-results.txt` (`runtime\test-results.txt` with the
   development set-up).
2. EURUSD, 1%, SL 25 pips: lots = 1% of equity ÷ $250, rounded down; reward at 2R = twice the risk.
3. Confirm a market BUY and a market SELL. In the Trade tab, the SL and TP equal the preview prices.
4. Switch to Pending, drag the entry line above and below the price, and check the type (table in
   section 4). Place one and check it in the Trade tab.
5. Drag the SL and TP lines: the fields switch to price and the money follows.
6. Close MT5 and open it again: the panel is back. Open a preview: SL/TP come back from the last order.
7. **Pin to new charts**, then open a new chart: the panel is on it.
8. Remove the EA: MT5's One-Click panel and the chart shift come back.
9. Hold **B** or press Enter right after typing in a field: no order is sent twice.
10. Switch Algo Trading off: the panel says so and sends nothing.
11. Turn MT5's One-Click Trading on, open a position, then drag its SL line. The card opens and the
    Trade tab still shows the old SL. Press Cancel: the line goes back. Drag it again and confirm: the
    Trade tab shows the new SL.
12. Drag SL, then TP, then confirm: both change in one go. Move the stop past the open price: allowed.
    Drag it past the market price: Confirm stays disabled and the card says why.
13. Place a Buy Limit and drag its entry: SL and TP follow at the same distance. Drag it above the
    price: the card refuses, because a Buy Limit must stay below the market.
14. Remove the EA: MT5's own trade lines come back.

Then repeat the checks you care about on the live account with the smallest lot.

## 11. Development

```
mql5/
  Experts/ActionInna/ActionInna.mq5     inputs, event handlers
  Include/ActionInna/
    App.mqh          state machine (idle > preview > sending > cooldown), modify card, commands, chart events
    RiskCalc.mqh     order plan: lots, money, checks; checks for changes to open trades
    SymbolSpec.mqh   symbol data, pip size, rounding
    Memory.mqh       SL/TP recall and settings files
    Panel.mqh        panel layout
    PreviewLines.mqh lines, zones and price tags on the chart
    OrderLines.mqh   lines of open trades, whose drags go to the modify card
    Trades.mqh       open positions and pending orders as the panel reads them
    Executor.mqh     permissions, filling modes, OrderSend, close, remove, SL/TP after slippage
    ChartGuard.mqh   chart settings changed while the EA runs, and their restore
    Bridge.mqh       the browser panel's requests (docs/protocol.md), answered with the same checks
    Link.mqh         which chart serves the browser panel, the named pipe, the link's key
    Json.mqh         JSON for the browser panel's messages
    SymbolMap.mqh    TradingView tickers to the broker's symbol names
    Hotkeys.mqh, Ui.mqh, Util.mqh, Defines.mqh
  Scripts/ActionInna/
    ActionInnaTests.mq5  worked examples and the test run
    Scenarios.mqh        generated scenario suites
    TestKit.mqh          counters, report, seeded random numbers
link/                  the link between the browser panel and MT5 (ActionInnaLink.exe)
  Program.cs       its modes, where it keeps its files, its key
  Host.cs          the browser side (Chrome's native messaging), the pipe to the EAs, starting MT5
  Installer.cs     --install and --uninstall: this Windows user only, no administrator rights
extension/             the browser side panel: plain JavaScript, no build step
  manifest.json    the side panel, the link (native messaging) and its own storage; TradingView tabs only when asked
  panel.html, panel.css, panel.js   the panel: what MT5 says, shown; what you type and press, sent
  lib/             numbers (format.js), the symbol of a TradingView tab (tv.js), the link connection (link.js)
  dev/mock.js      a stand-in for the link and MT5, for working on the panel in a plain tab (not published)
scripts/
  link-mt5.ps1     junctions into the MT5 data folder (-Unlink removes them)
  build.ps1        MetaEditor command-line build, logs in build\
  build-link.ps1   builds build\ActionInnaLink.exe with the C# compiler that comes with Windows
tests/native/
  run.sh           the same sources compiled with g++ against a fake MT5, then every test run
  mql.h            the fake MT5: types, strings, checked arrays, chart objects, symbol, and a trade
                   server that applies a broker's rules (filling, expiry, order types, netting, ...)
  mql2cpp.js       copies the sources with the few changes g++ needs (the originals are untouched)
  brokers.h        the symbols and the nine broker set-ups every test runs against
  suites.cpp       ActionInnaTests over several seeds and made-up symbols, then at every broker set-up
  app.cpp          drag-and-confirm, slippage and broker scenarios, and a random fuzz against the real panel code
  bridge.cpp       the browser panel's side: JSON (with a fuzz), every request at every broker set-up,
                   which chart serves the panel, and the pipe and its key byte for byte
tests/link/
  run.js           plays Chrome and up to three EAs against the built link, and runs its installer
tests/extension/
  run.mjs          the side panel's libraries: numbers, TradingView symbols, requests and their replies
  serve.js         serves extension/ to a plain browser tab, where dev/mock.js stands in for the link
docs/
  protocol.md      how the browser panel, the link and the EA talk
```

- **The link**: `scripts\build-link.ps1` builds it. Then, once, `build\ActionInnaLink.exe --install --dev`
  registers it for Chrome, Edge, Brave and Chromium (this Windows user) and points them at `build\`.
  `node tests/link/run.js` tests it without touching that set-up: its files and its pipe go to
  `tests/link/out`, and the registry is left alone. CI builds and tests it on Windows.

- **The side panel**: in Chrome, open `chrome://extensions`, turn on Developer mode, and **Load
  unpacked** the `extension` folder. It gets the development ID that `--dev` registered, so the link
  answers it. Its toolbar button opens the panel. To work on the panel without MT5, run
  `node tests/extension/serve.js` and open <http://127.0.0.1:8137/panel.html>: `extension/dev/mock.js`
  plays the link and MT5, and the address picks a scene (`?terms=2`, `?scene=nomt5`, the rest are in
  that file). `node tests/extension/run.mjs` tests its libraries; CI runs it.

- **Native tests**, without MT5 (needs Git Bash, Node.js and g++ 9 or newer):
  `bash tests/native/run.sh [seeds] [rounds] [fuzz runs] [fuzz seed]`. It runs ActionInnaTests on seven
  made-up symbols, then the live suites at nine broker set-ups (`tests/native/brokers.h`), then drives
  the real panel code through drags, releases, clicks, typing, keys and server events, at every set-up.
  Every request that reaches the fake server is checked: it must come from a Confirm, pass the checks
  against what the server has at that moment, keep SL and TP, and be one that set-up's server accepts.
  It ends with "native tests: all passed". CI runs it on every push. It does not replace a run in MT5:
  MetaEditor's compiler, real prices and the real server are not part of it.

- Edit here, run `scripts\build.ps1`, then restart MT5 or drag the EA onto the chart again: a chart
  keeps running the old code until the EA is loaded again. You can also press F7 in MetaEditor: the
  junctions make the files appear there.
- Remove the links with `scripts\link-mt5.ps1 -Unlink`. Never delete a junction with
  `Remove-Item -Recurse`: Windows PowerShell 5.1 follows it and deletes this repository's files.
- `*.ex5`, logs, `build\`, `runtime\` and `mt5.local.json` stay out of git.
- How to contribute: [CONTRIBUTING.md](CONTRIBUTING.md). Wrong or unexpected orders are reported
  privately: [SECURITY.md](SECURITY.md). Changes per version: [CHANGELOG.md](CHANGELOG.md). Community
  rules: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Design decisions and colours: [DESIGN.md](DESIGN.md).

## 12. Licence and risk

MIT licence, see [LICENSE](LICENSE).

ActionInna sends real orders to your broker. A bug, a wrong input, slippage or a price gap can lose
money. It comes with no warranty: test it on a demo account first and use it at your own risk. Nothing
here is financial advice.

ActionInna is an independent project, not affiliated with or endorsed by Exness or MetaQuotes.
MetaTrader and MQL5 are trademarks of MetaQuotes.
