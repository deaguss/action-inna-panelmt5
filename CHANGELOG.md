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

### Fixed

- Symbol data (stops and freeze levels) is read again right before an order or a change is sent. The
  timer reads it once a second, so a broker change within that second could let a request through
  that the server would refuse.
- A line dragged while an order or change was being sent (and so not taken) went back to its place
  only when its value changed; it now goes back when the mouse is released.

### Changed

- The test report no longer records the broker's server name.

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
