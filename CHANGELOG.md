# Changelog

All notable changes to ActionInna are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Changing open trades with a confirm pop-up. ActionInna draws its own lines for every position and
  pending order on the chart's symbol, in place of MT5's own trade lines, which can change an order the
  moment a drag ends. Dragging SL, TP or a pending order's entry opens a modify card with the new
  prices, the money and % at each level, and the risk : reward. Nothing is sent until Confirm. Cancel
  or Esc puts the lines back.
- A pending order's SL and TP move with its entry. A position's stop may go to break-even or past it.
  The card checks stops and freeze levels and the required SL/TP. The safety cap blocks a change only
  when the risk goes up.
- Input "Drag open trades with a confirm pop-up" (on by default). MT5's own trade lines come back when
  it is off or the EA is removed.
- Tests: worked examples and generated suites for changes to open trades (against a whole-point
  reference, entry moves, and 2,000 changes on the chart's symbol with live prices); about 114,000
  scenarios per round.
- Native tests (`tests/native/run.sh`): the same sources compiled with g++ against a fake MT5, with
  drag-and-confirm scenarios and a random fuzz that checks every request the fake server receives.
- Slippage handling. When a market order fills a tick or more away from its planned entry, the input
  "When a market order fills at another price" decides what happens to its SL and TP:
  - Follow the SL mode (the default): levels in pips or R move with the fill, so an SL in pips keeps
    the planned risk, and levels set as a price stay.
  - Keep them where they were set.
  - Move both with the fill.
  The order always carries its SL and TP. A move is a second request, checked like any change to an
  open trade. The status line reports the slippage and the risk at the stop.
- Broker set-ups in the native tests (`tests/native/brokers.h`). Every live suite, the panel's orders
  and the fuzz run at nine set-ups, against a fake server that applies each one's rules: filling per
  execution mode, expiry types, order types, SL/TP allowed, volume and price grids, stops and freeze
  levels, netting, no opposite positions, FIFO closes, requotes and slippage.
- CI runs the native tests on every push.

### Fixed

- Gold behind a broker prefix (`#XAUUSD`, `m.XAUUSD`) got a forex pip instead of 0.1 in the Trader
  convention. Gold is now also recognised by its base currency, XAU.
- On an account that allows no opposite positions, an order against an open position reached the
  broker and was refused there. The panel now refuses it first and says why. A pending order gets a
  warning instead.
- Money now shows with the account currency's decimals (JPY with none), not always two.

- Symbol data (stops and freeze levels) is read again right before an order or a change is sent. The
  timer reads it once a second, so a broker change within that second could let a request through
  that the server would refuse.
- A line dragged while an order or change was being sent (and so not taken) went back to its place
  only when its value changed; it now goes back when the mouse is released.

### Changed

- The test report no longer records the broker's server name.
- The pip convention "Exness" is now called "10 points" (it counts 10 points per pip on every
  symbol); saved settings keep working.
- The "Max slippage" input says it applies to instant and request execution only, which is what MT5
  does.
- Open positions and pending orders are read in `Trades.mqh`, shared by the chart lines and the
  slippage handling.

## [1.0.0] - 2026-10-21

First public version (EA version 1.00). Release notes: [docs/releases/v1.0.0.md](docs/releases/v1.0.0.md).

### Added

- Risk trade panel for MT5 desktop that replaces the One-Click panel: SELL/BUY with live prices, risk
  presets 1% / 1.5% / 2% plus a custom value in %, money or fixed lots, and the lot size worked out
  from the stop.
- Stop loss in pips or price, take profit in pips, price or R.
- Preview before sending: entry, SL and TP lines with price, pips, money and % tags, draggable.
  Nothing is sent until CONFIRM. One-click trading is optional and off by default.
- Market and pending orders; a pending order's type follows its entry price.
- Recall of earlier SL/TP per symbol ("Set SL/TP automatically", Last buttons, R key), stored as price
  distances so they mean the same at every broker.
- Hotkeys, and Tab / Shift+Tab focus through every control with a visible focus ring.
- Slim layout, chosen or forced on charts too short for the full panel.
- Pin to new charts (default template) and Save template.
- Checks before sending: stops level, symbol trade and order modes, free margin, a risk cap, filling
  modes tried in turn, expiry modes for pending orders.
- Dark and light themes that follow the chart, with every text pair at 4.5:1 or more.
- `link-mt5.ps1` and `build.ps1` for a linked development set-up; `ActionInnaTests` with worked
  examples and about 92,000 generated scenarios per round.

[Unreleased]: https://github.com/deaguss/action-inna-panelmt5/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/deaguss/action-inna-panelmt5/releases/tag/v1.0.0
