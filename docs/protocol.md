# Browser panel protocol (version 1)

How the browser side panel, the link (`ActionInnaLink.exe`) and the ActionInna EA in MT5 talk. The
EA keeps every rule and every number. The panel only shows them and sends what the trader typed and
pressed.

```
side panel  <-- native messaging -->  link  <-- named pipe \\.\pipe\ActionInna.Link -->  ActionInna EA (one chart per MT5)
```

## Frames

Every message is a JSON object, sent as a frame: a 4-byte little-endian length, then that many bytes
of UTF-8. Chrome's native messaging frames messages this way, and the pipe uses the same frames, so
the link only has to pass them on.

- A frame carries at most 1 MiB.
- Unknown keys are ignored. A frame that isn't a JSON object gets an `error` message back.

## The link's key

Named pipes are shared by every Windows user of a PC, so on a shared machine (a VPS several people
log in to) another user could serve a pipe with the same name. The link guards against that:

1. It keeps a random key of 32 hex characters in `Common\Files\ActionInna\link.key`, under this
   Windows user's AppData, which other users can't read. It creates the file if it's missing.
2. Its first frame to an EA is the key:

   ```json
   {"t":"link","key":"0f1e2d3c4b5a69788796a5b4c3d2e1f0"}
   ```

3. The EA reads the same file:
   - It serves nothing until a frame with the matching key arrives.
   - It drops a connection that sends a wrong key, or none within 3 seconds.
   - With no `link.key` file, it serves nothing at all.

The link never passes the key to the panel. The pipe itself also only lets this Windows user in.

## Who is who

- **Terminal:** one MT5 terminal, logged in to one account. In each terminal, the ActionInna EA on
  exactly one chart serves the panel (the *host*). Another chart's ActionInna takes over within a few
  seconds if the host chart closes.
- **`term`:** the link numbers the terminals it serves (`"1"`, `"2"`, ...).
  - It adds `term` to every message it passes from an EA to the panel.
  - The panel puts `term` on every request, and the link delivers the request to that terminal only.
  - The EA ignores `term`.

## The link's own messages

The link tells the panel what it sees. These are `link` messages; `term` is there when one terminal
is meant:

```json
{"t":"link","state":"terminal-connected","term":"1","text":"12345678@Broker-Demo"}
```

| `state` | Meaning |
|---|---|
| `listening` | The link runs; EAs can connect |
| `terminal-connected` | An MT5 serves the panel; `text` is its account |
| `terminal-gone` | That MT5 stopped serving it (MT5 closed, or another chart of the same account took over) |
| `starting-mt5` | The link started MT5, because none was connected 3 seconds after the panel opened |
| `no-ea` | MT5 runs, but no chart serves the panel; `text` says what to do |
| `no-mt5` / `mt5-missing` / `mt5-failed` | No MT5 is set up, it moved, or it could not be started; `text` says what to do |
| `pipe-failed` | The pipe could not be made |
| `busy` | The panel is already open in another browser window; this copy of the link stops |

The panel can ask the link two things; they never reach an EA:

- `{"t":"link.status"}`: the link sends `listening`, then `terminal-connected` for every terminal.
- `{"t":"link.start"}`: start the MT5 terminals the installer recorded, now (the panel's "Start
  MT5" button).

A request whose `term` is unknown or missing is answered by the link with `ok:false` and "MT5 is not
connected". When exactly one MT5 is connected, a request without `term` goes to it.

## Requests and replies

- Every request from the panel has a type `t` and an `id`: a positive integer, unique while the panel
  is open.
- The EA answers each request with exactly one `reply`, carrying the same `id`:

```json
{"t":"reply","id":12,"ok":true, ...}
{"t":"reply","id":13,"ok":false,"err":"Set a stop loss"}
```

- `ok:false` means the request was not carried out. `err` says why, in words the panel can show as
  they are.
- A preview that finds a problem is still `ok:true`: the problem is in the plan's `err`.

Values the panel sends as words:

| Key | Values |
|---|---|
| `side` | `"buy"`, `"sell"` |
| `slMode` | `"pips"`, `"price"` |
| `tpMode` | `"pips"`, `"price"`, `"r"` |
| `riskMode` | `"percent"`, `"money"`, `"lots"` |
| `riskBase` | `"equity"`, `"balance"` |

## Writes: preview, then confirm

Nothing changes in MT5 from a single message. Every write is two steps:

1. A preview request (`preview`, `modPreview`, `closePreview`). The EA checks it, values it, and
   answers with a `preview` id such as `"p17"`.
2. The confirm request (`send`, `modSend`, `close`) names that id.

Before acting on a confirm, the EA checks everything again with the newest prices and the trade as
the server has it now. It refuses:

- an unknown preview id;
- a preview id that was already used;
- a preview older than 60 seconds;
- a preview made on another account than the one MT5 is logged in to now;
- a new order whose risk grew more than 5% since the preview;
- anything the checks refuse now.

`cancel` (remove a pending order) is a single request: repeating it can't do harm. The panel still
asks the trader first.

## Messages the EA sends on its own

### `terminal`

Sent once the link's key matches, and again whenever any of its values change.

```json
{"t":"terminal","ver":1,"login":12345678,"server":"Broker-Demo","company":"Broker Ltd","currency":"USD",
 "currencyDigits":2,"tradeMode":"demo","marginMode":"hedging","hedgeAllowed":true,"fifo":false,
 "connected":true,"problem":"",
 "settings":{"presets":[1,1.5,2],"riskBase":"equity","maxRiskPct":5,"commissionRT":0,"requireSL":true,
   "requireTP":true,"pipMode":"trader","defaultSLPips":20,"defaultTPMode":"r","defaultTPValue":2,
   "pendingOffsetPips":10,"slipPolicy":"follow"}}
```

- `tradeMode`: `"demo"`, `"contest"` or `"real"`.
- `marginMode`: `"hedging"`, `"netting"` or `"exchange"`.
- `connected`: MT5's connection to the broker.
- `problem`: what stops sending now, in words, such as `"Turn on Algo Trading (toolbar button) to send
  orders"`. Empty when nothing does.
- `settings` are the EA's inputs. The panel shows them, but can't change them: the safety cap,
  required SL/TP, commission and the rest stay in MT5.
- `pipMode`: `"trader"`, `"10points"` or `"points"`.
- `slipPolicy`: `"follow"`, `"keepPrices"` or `"keepRisk"`.

### `quote`

For the symbol the panel watches (`watch`): at most 10 a second, and only when the price changed.

```json
{"t":"quote","symbol":"XAUUSDm","bid":2650.12,"ask":2650.28,"spreadPips":1.6,"timeMsc":1792000000123}
```

### `trades`

Every open position and pending order, on every symbol, and the account's money. Sent once the
link's key matches, when a trade changes, and every second while positions are open (for the
profit).

```json
{"t":"trades","balance":10000,"equity":10012.4,"margin":530.1,"freeMargin":9482.3,"list":[
 {"ticket":4327679330,"symbol":"XAUUSDm","kind":"position","type":"BUY","side":1,"lots":0.2,"open":2650.58,
  "sl":2645.58,"tp":2660.58,"profit":12.4,"digits":3,"openMsc":1792000000123},
 {"ticket":4327679331,"symbol":"EURUSDm","kind":"order","type":"SELL LIMIT","side":-1,"lots":0.5,"open":1.0901,
  "sl":1.0921,"tp":1.0861,"profit":0,"digits":5,"expiration":0,"locked":false}]}
```

- `profit` includes swap.
- `locked` marks a stop-limit order. The panel can't change one; MT5's Trade tab can.

### `beat`

Sent by the EA after a second without any other message, so the panel knows MT5 is alive. The EA
also learns this way when the link has gone: the write fails.

```json
{"t":"beat"}
```

### `error`

A frame the EA could not read.

```json
{"t":"error","err":"Not a JSON object"}
```

## Requests

### `symbols`: TradingView ticker to broker symbols

```json
{"t":"symbols","id":1,"ticker":"OANDA:XAUUSD"}
-> {"t":"reply","id":1,"ok":true,"ticker":"XAUUSD","pick":"XAUUSDm",
    "candidates":[{"name":"XAUUSDm","description":"Gold vs US Dollar","visible":true}]}
```

How a ticker finds the broker's symbol:

1. The exchange prefix (`OANDA:`) is dropped.
2. The EA looks for symbols in this order:
   - the same name;
   - the same name with a prefix or suffix (`#XAUUSD`, `XAUUSD.r`, `XAUUSDm`);
   - a known other name for the same market (`GOLD` for XAUUSD, `US30`, `DJ30` or `WS30` for the Dow);
   - for a six-letter pair, the same base and profit currencies.
3. Market Watch symbols come first.

`pick` is the trader's earlier choice for this ticker on this server, if it still exists. Otherwise
it's the best match when that is clear, and empty when it isn't.

### `pick`: remember the trader's choice

```json
{"t":"pick","id":2,"ticker":"XAUUSD","symbol":"XAUUSDm"}  -> {"t":"reply","id":2,"ok":true}
```

The choice is kept per server and ticker, in `Common\Files\ActionInna\symbols.txt`.

### `watch`: the symbol the panel shows

```json
{"t":"watch","id":3,"symbol":"XAUUSDm"}
-> {"t":"reply","id":3,"ok":true,"spec":{"symbol":"XAUUSDm","digits":3,"point":0.001,"tickSize":0.001,
    "pipSize":0.1,"volMin":0.01,"volMax":200,"volStep":0.01,"stopsLevel":0,"freezeLevel":0,
    "execution":"market","tradeMode":"full","orders":{"market":true,"limit":true,"stop":true,"sl":true,"tp":true},
    "contractSize":100,"base":"XAU","profit":"USD"}}
```

Quotes for that symbol follow.

### `preview`: a new order

```json
{"t":"preview","id":4,"symbol":"XAUUSDm","side":"buy","pending":false,"entry":0,
 "slMode":"pips","slValue":50,"tpMode":"r","tpValue":2,"riskMode":"percent","riskValue":1,"riskBase":"equity"}
-> {"t":"reply","id":4,"ok":true,"preview":"p1","plan":{"valid":true,"err":"","warn":"","type":"BUY",
    "entry":2650.28,"sl":2645.28,"tp":2660.28,"lots":0.2,"riskMoney":100,"riskPct":1,"rewardMoney":200,
    "rewardPct":2,"rr":2,"slPips":50,"tpPips":100,"pipValue":2,"margin":530.06,"freeAfter":9469.94,
    "commission":0,"spreadPips":1.6,"bid":2650.12,"ask":2650.28}}
```

This is `AiBuildPlan`, as on the chart.

### `send`: send a previewed order

```json
{"t":"send","id":5,"preview":"p1"}
-> {"t":"reply","id":5,"ok":true,"ticket":4327679330,"type":"BUY","pending":false,"price":2650.58,"lots":0.2,
    "fill":{"slipped":true,"slipPips":3,"slMoved":true,"tpMoved":true,"notMoved":"","sl":2645.58,"tp":2660.58,
    "risk":100,"plannedRisk":100}}
```

- The order always carries its SL and TP.
- After a market order fills at another price, SL and TP move as the EA input "When a market order
  fills at another price" says. `fill` reports what happened.
- On instant and request execution, a requote is tried again at the new price, up to three times,
  as on the chart.

### `recall`: earlier SL/TP for a symbol

```json
{"t":"recall","id":6,"symbol":"XAUUSDm","side":"buy","entry":0,"which":"both","back":0}
-> {"t":"reply","id":6,"ok":true,"slMode":"pips","slValue":50,"tpMode":"r","tpValue":2,"desc":"SL 50 pips, TP 2R",
    "index":0,"count":3}
```

- `which` is `"sl"`, `"tp"` or `"both"` (the default): the levels to bring back. `desc` names only
  those, and only they are meant; the others in the reply are the defaults.
- `back` steps through the remembered records: 0 is the newest. A record that holds nothing for
  `which` is skipped, as with the chart's Last buttons. `index` is the record used, so the next
  press asks for `index + 1`.
- `count` is the number of records. With none, the levels come from the last trade on the symbol in
  the account's history, and `count` is 0.
- `entry` is a pending order's entry; 0 means the market price.
- A price level that no longer fits on the right side of the entry comes back as a distance, as on
  the chart.

### `modPreview` / `modSend`: change an open trade

```json
{"t":"modPreview","id":7,"ticket":4327679330,"sl":2647.00,"tp":2660.58}
-> {"t":"reply","id":7,"ok":true,"preview":"p2","mod":{"valid":true,"changed":true,"err":"","warn":"",
    "open":2650.58,"sl":2647.0,"tp":2660.58,"slMoney":-71.6,"slPct":-0.72,"oldSlMoney":-100,"tpMoney":200,
    "tpPct":2,"rr":2.79,"slPips":35.8,"tpPips":100}}
{"t":"modSend","id":8,"preview":"p2"}  -> {"t":"reply","id":8,"ok":true,"ticket":4327679330}
```

- A pending order may also send `open`, its new entry.
- This is `AiBuildModPlan`, as on the chart's modify card.

### `closePreview` / `close`: close a position, or part of it

```json
{"t":"closePreview","id":9,"ticket":4327679330,"lots":0.1}
-> {"t":"reply","id":9,"ok":true,"preview":"p3","close":{"valid":true,"err":"","lots":0.1,"left":0.1,
    "price":2655.10,"profit":45.2}}
{"t":"close","id":10,"preview":"p3"}  -> {"t":"reply","id":10,"ok":true,"ticket":4327679330,"price":2655.08,"lots":0.1}
```

- `lots` of 0 closes all of the position.
- A part close must leave at least the symbol's minimum lot.
- On an account that closes first in, first out, only the oldest position on the symbol can be
  closed, and the preview says which.
- `profit` is MT5's profit for those lots at the current price, swap included, commission not.

### `cancel`: remove a pending order

```json
{"t":"cancel","id":11,"ticket":4327679331}  -> {"t":"reply","id":11,"ok":true}
```

The broker's freeze level is checked first. A stop-limit order can be removed too.
