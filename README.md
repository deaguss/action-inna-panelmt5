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
- **Recall of earlier SL/TP** per symbol, like Exness's "Set SL/TP automatically".
- **Hotkeys** for the presets, buy/sell preview, confirm and cancel.
- **Stays put**: MT5 reopens it with your charts. "Pin to new charts" puts it on every new chart too.

It is an Expert Advisor (MQL5), so it runs inside MT5 with MT5's own prices and order execution.

**What has been tested so far:**

- It compiles with 0 errors and 0 warnings in MetaEditor (MT5 desktop for Windows).
- On an Exness demo account (hedging, USD):
  - a pending SELL STOP was placed through the panel, with its SL and TP;
  - Pin to new charts works, and so does reopening MT5 with the panel back on its charts;
  - the risk numbers on the panel match a hand calculation.
- Not yet tried: market orders through the panel, the rest of the checklist in section 10, other brokers,
  and MT5 on Mac or Linux. If you run it there, open an issue with what you saw.

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
| Exness (1 pip = 10 points everywhere) | 0.0001 | 0.01 | 0.01 | 500 pips |
| Points | 1 point | 1 point | 1 point | 5,000 points (3-digit gold) |

The lot size and money do not depend on the convention, only the pip numbers do.

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
| | Max slippage | 10 points (instant execution only) |
| | Order comment | ActionInna |
| Hotkeys | Keys, see section 5 | |
| Display | Hide MT5's One-Click panel | on |
| | Shift the chart for the panel | on |
| | Shade the risk / reward zones | on |
| | Theme | Auto (follows the chart background) |
| | Panel scale | 1.0 (follows the Windows display scale) |
| | Font / size | Arial 9 (on every Windows PC, so the text keeps the sizes the layout was measured for) |
| | Sounds | on |
| | Log file | on: `MQL5\Files\ActionInna\log.txt` |

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
| Anything else | The log: `MQL5\Files\ActionInna\log.txt` (with the dev set-up: `runtime\log.txt` here) |

## 10. Test checklist (demo account first)

1. Run the **ActionInnaTests** script (Navigator > Scripts > ActionInna, drag it onto any chart, press
   OK). It runs the worked examples, then about 92,000 generated scenarios: lot sizing, rounding,
   order types, SL/TP checks against an independent reference, recall files (including damaged ones),
   typed numbers, hotkey names, pip sizes, money formatting, and 2,000 full order plans on the chart's
   symbol with live prices. It sends no orders. Every suite should say "all passed". Raise **Rounds**
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

Then repeat the checks you care about on the live account with the smallest lot.

## 11. Development

```
mql5/
  Experts/ActionInna/ActionInna.mq5     inputs, event handlers
  Include/ActionInna/
    App.mqh          state machine (idle > preview > sending > cooldown), commands, chart events
    RiskCalc.mqh     order plan: lots, money, checks
    SymbolSpec.mqh   symbol data, pip size, rounding
    Memory.mqh       SL/TP recall and settings files
    Panel.mqh        panel layout
    PreviewLines.mqh lines, zones and price tags on the chart
    Executor.mqh     permissions, filling modes, OrderSend
    ChartGuard.mqh   chart settings changed while the EA runs, and their restore
    Hotkeys.mqh, Ui.mqh, Util.mqh, Defines.mqh
  Scripts/ActionInna/
    ActionInnaTests.mq5  worked examples and the test run
    Scenarios.mqh        generated scenario suites
    TestKit.mqh          counters, report, seeded random numbers
scripts/
  link-mt5.ps1     junctions into the MT5 data folder (-Unlink removes them)
  build.ps1        MetaEditor command-line build, logs in build\
```

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
