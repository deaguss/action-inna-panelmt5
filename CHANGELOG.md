# Changelog

All notable changes to ActionInna are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
