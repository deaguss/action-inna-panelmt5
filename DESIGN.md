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
| Focal point | The SELL/BUY pair when idle, CONFIRM during a preview, the card's Confirm while a change is open | One question per moment: which side, then go or not |
| Changing open trades | A drag only moves the line; a card beside the panel, level with the dropped line, holds the change until Confirm | A drag is easy to make by accident; a change to a live trade should take a second, deliberate press |
| Card colours | Confirm in the trade's side colour, Cancel neutral, the server's old level as a muted dotted line | Same reading as CONFIRM, and the old and new levels can be told apart at a glance |
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

## The browser side panel

The same panel in Chrome's side panel, next to TradingView (`extension/`). The decisions above hold,
except where this table says otherwise.

| Area | Decision | Reason |
|---|---|---|
| Layout | Three sections: the account; the symbol, its prices and the order form; the open trades with their cards | The order in which a trade is decided; the list stands in for the chart's trade lines |
| Header | The account and DEMO/REAL; under it equity and free margin, or, in amber, whatever stops trading | One line that is useful whether things are fine or not |
| Prices | SELL, spread, BUY in one bar; the price is the large type, the side name small | The number a trader reads is the price; one place for it, not a quote line repeating the buttons |
| Order type | Market and Pending as one two-part switch, the entry beside it | A single toggle labelled with its state reads as an action; both choices visible say which is on |
| Rows | One label column for Risk, Stop loss and Take profit; unit and mode buttons of one width | The fields start and end at the same place, so the eye runs down one column |
| Numbers | Only while a preview is open: Lots and Risk in large type first, the rest below; two pairs to a row on a wide panel | Idle, SELL/BUY are the focal point; previewing, Confirm and what it risks are |
| Messages | Under Confirm, taking no room when there is none; on a card, above its Confirm with two lines kept | Nothing above a Confirm button may move it under the cursor |
| Trades | Rows parted by a line, actions small; the card the one bordered surface | A list reads as one list; the change being made stands out |
| Width | Works from 320px, Chrome's narrowest side panel | The panel shares the window with the chart |
| Redraws | Built once and updated in place four times a second; trade rows kept per ticket; a card built once per opening | A redraw never takes a click, a cursor or an open list |
| Confirm | Off until MT5's numbers for the latest input are in, then 0.3 s more | A click on numbers that just changed is not a decision on them |
| Typed prices | A typo stops the preview with words; only an empty field means none | "No stop loss" must never come from a slip of the finger |
| Status | An error or warning about the plan beats a passing message | What stops the order has to be seen at once |
| Lost answers | "May have gone through: check Open trades", never "not sent" | A trader who believes nothing was sent may send it twice |
| Keyboard | Tab through every control, Enter in the symbol field, Esc closes a card or the preview; no global hotkeys | The browser's and TradingView's shortcuts stay theirs |
| Symbol | Always the TradingView chart's, shown as text with a line saying where it comes from or why it stays put; nothing to type | The trader picks the chart in TradingView; the panel should never make them pick it twice |
| Chart lines | TradingView's own order lines: entry grey, SL red, TP green, with the money on them; preview solid, open trades dashed, a change not sent yet solid with "(not sent)" | The colours of the chart panel's levels, in the line style traders know from TradingView's broker connections |
| Dragging lines | Changes the preview, or opens the trade's change card; never sends | The same deliberate second press as on the MT5 chart |
| Options | The chart menu's auto SL/TP and risk base, folded under Options; no one-click trading | Set once and left alone; in a browser, a stray click is closer at hand than on a chart |
| Icon | A long-position box: TP above the entry line, SL below, at 2R, on the dark panel colour | Traders know the shape from TradingView's position tool, and it still reads at 16px |
| Theme | Follows the browser (`prefers-color-scheme`), with the colours below | No chart background to follow |

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
(`mql5/Include/ActionInna/Ui.mqh`) and, for the side panel, in `extension/panel.css`; change them
together.
