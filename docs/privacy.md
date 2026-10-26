# ActionInna privacy policy

This covers the ActionInna side panel (the browser extension), the ActionInna link
(`ActionInnaLink.exe`) and the ActionInna EA in MetaTrader 5. All three run on your PC, and none of
them sends anything over the network: no analytics, no crash reports, no servers of ours. Nothing is
sold or shared: ActionInna sends nothing off your PC. The one thing another party can see is the
lines drawn on TradingView's chart, which TradingView's page can read (below).

## What the side panel handles

- **From your own MT5, through the link:** the account's login, server, broker name, currency,
  balance, equity and margin; your open positions and pending orders; the prices of the symbol you
  watch; the EA's settings. The panel shows them, and keeps none of them after it closes.
- **What you type and choose:** the risk preset, your own risk values, the SL/TP modes and values,
  the options, and the symbol you last used on each account. These are kept in the browser's storage
  for this extension (`chrome.storage.local`), on this PC only, so the panel opens the way you left
  it. The last symbol is filed under the account's login and server.
- **TradingView tabs, once you allow it:** the panel takes its symbol from TradingView's chart, after
  you allow access to `tradingview.com` and its country sites (one click in the panel, then the
  browser's own prompt). With that access:
  - It reads the address and title of the TradingView tab in front of its window, to tell which
    symbol it shows, and closes itself when that tab is not TradingView. Of other sites' tabs the
    browser shows it nothing.
  - It puts two small scripts of its own into that TradingView tab. They draw the panel's lines on
    the chart (your order and your open trades, with their prices, lots and money), and tell the
    panel when you drag one. The scripts read nothing else on the page, and send nothing anywhere
    but to the panel. When the panel closes, the lines go.
  - **What TradingView can see:** the lines are drawn by TradingView's own chart code, inside its
    page. TradingView's scripts, and any other script running on its page, can read them while they
    are there: the prices, lots and money of your previewed order and of your open trades on that
    symbol. ActionInna sends them nowhere, but can't stop the page from reading what is drawn on it.

  You can remove the access in the browser's extension settings. The panel then has no symbol to
  work with.

The panel talks only to the link, through the browser's native messaging. It makes no network
requests.

## What the link and the EA keep on your PC

- `%LOCALAPPDATA%\ActionInna`: the installed link, the file that tells the browsers where it is,
  `link.json` (the MT5 terminals it may start), and `link.log`. The log records when the link and
  terminals start and stop. When one MT5 replaces another for the same account, it names the account
  by login and server.
- MT5's `Common\Files\ActionInna` folder: `link.key` (a random key that only your Windows user can
  read), `symbols.txt` (which broker symbol you picked for a TradingView ticker, per server), and the
  EA's own files: earlier SL/TP per symbol and the panel's settings.
- In the registry, under `HKEY_CURRENT_USER` only: one key per browser that points it at the link.

The link talks to MT5 through a named pipe that only your Windows user can open, and only from this
PC. It opens no network port.

## Removing it

- Remove the extension in the browser: its storage goes with it.
- Run `ActionInnaLink.exe --uninstall`. It removes the registry keys, the file that points the
  browsers at the link, `link.json` and `link.key`. It also removes the installed link, or, when
  you run it from that copy, asks you to delete it once its window is closed.
- What stays: `link.log` (delete the `%LOCALAPPDATA%\ActionInna` folder to remove it), `symbols.txt`
  and the EA's files in MT5's `Common\Files\ActionInna`, and the EA in MT5. You can delete all of
  them at any time.

## Questions

Open an issue in the repository, <https://github.com/deaguss/action-inna-panelmt5>. Never post
account numbers, passwords or logs that name your account.
