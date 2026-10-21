# ActionInna design

Direction comes from the owner's brief: the order panel of the Exness web terminal, moved onto the MT5
desktop chart. This file records the decisions made on that brief and the reason for each, so a change
can be checked against them.

**Design read:** an order panel for discretionary MT5 traders, in the style of the Exness order form.
**Dials:** ENERGY 1 / RHYTHM 1 / MOTION 1. It is a tool used for a few seconds per trade, next to a
moving chart: it should be calm, predictable and still.

## Decisions

| Area | Decision | Reason |
|---|---|---|
| Layout | One column: side, risk, SL/TP, money, confirm | The order in which a trade is decided, top to bottom |
| Focal point | The SELL/BUY pair when idle, CONFIRM during a preview | One question per moment: which side, then go or not |
| Placement | Docked at the chart's right edge, chart shifted to make room | Keeps the latest candles visible, like a sidebar |
| Slim layout | SELL / risk / BUY bar, chosen or forced by a short chart | CONFIRM must stay on screen on tiled charts |
| Colour: sides | Blue = BUY, red = SELL, and nothing else | The convention traders already read at a glance |
| Colour: levels | Green TP, red SL, neutral entry line | The tag names the side, so the entry line needs no colour |
| Colour: state | Selected controls are neutral (text-coloured edge, bold) | Keeps blue meaning BUY, even during a SELL preview |
| Colour: status | Amber warning, red error, green done, always with words | The words carry the meaning; colour only speeds reading |
| Typeface | Arial, 9pt base, nothing below 8pt | On every Windows PC, so the measured layout holds |
| Shapes | Square corners, flat fills, 1px edges | MT5 chart objects draw no rounded corners; flat reads fastest |
| Spacing | 10px panel padding, 4px gaps, 24px rows | Dense enough for a sidebar, every control at least 24x24px |
| Motion | None | A moving chart is next to it; the panel stays still |
| Keyboard | Hotkeys for the main actions, Tab through every control | Trading without the mouse, and a visible focus ring |

## Colours and measured contrast

Text needs 4.5:1 and control edges 3:1 (WCAG 2.x, computed, not estimated).

| Role | Dark | Light |
|---|---|---|
| Panel | `23,25,31` | `255,255,255` |
| Text on panel | `232,234,239`, 14.6 | `28,31,38`, 16.5 |
| Muted text on panel | `142,149,163`, 5.8 | `100,107,120`, 5.4 |
| Field and button edges | `104,110,124`, 3.4 | `128,134,146`, 3.7 |
| BUY fill, white text | `36,104,214`, 5.2 | `20,98,212`, 5.6 |
| SELL fill and SL tag, white text | `200,48,62`, 5.3 | `198,40,56`, 5.6 |
| Idle BUY text on its tint | `115,170,255`, 6.3 | `16,86,190`, 5.7 |
| Idle SELL text on its tint | `255,125,136`, 6.2 | `176,30,46`, 5.7 |
| TP tag, white text | `22,124,74`, 5.2 | `18,120,68`, 5.5 |
| Entry tag, white text | `82,88,102`, 7.1 | `72,78,92`, 8.3 |
| Selected control, text on it | `52,57,70`, 9.6 | `228,231,237`, 13.3 |
| Warning text | `242,177,80`, 9.4 | `150,90,0`, 5.6 |
| Error / risk text | `255,110,110`, 6.5 | `196,36,48`, 5.8 |
| Done / reward text | `72,200,125`, 8.2 | `16,122,62`, 5.4 |

The theme follows the chart background (input "Theme"). The values live in `AiBuildTheme`
(`mql5/Include/ActionInna/Ui.mqh`); change both together.
