# Security policy

ActionInna places orders on a real trading account, so some bugs cost money. Report those privately.

## What to report privately

- An order sent without a preview and a confirm (with one-click trading off).
- An order sent with a different side, type, volume, entry, SL or TP than the preview showed.
- A lot size that risks more than the risk you set.
- Anything written outside MT5's own file folders, or any network access, by the EA.
- For the browser side panel and its link:
  - a web page, another extension or another Windows user who can reach the link or its pipe, or
    make the EA act;
  - a write that MT5 carries out without its preview and confirm, or a preview confirmed twice;
  - the panel or the link sending anything over the network;
  - the link writing outside `%LOCALAPPDATA%\ActionInna`, MT5's `Common\Files\ActionInna`, MT5's
    `Experts` folders (`--install` only) and its own keys under `HKEY_CURRENT_USER`.

Other bugs, including wrong numbers on the panel that never reach an order, go to the public issue
tracker.

## How the browser panel is guarded

Everything runs on your PC. These are the paths an order could take, and what guards each:

- **The browser:** it starts the link only for the extension IDs in the link's manifest. Web pages
  can't use native messaging, and neither can other extensions. The download's installer allows the
  store IDs only. The unpacked panel's development ID comes from a public key, so any unpacked
  extension could carry it: only `--install --dev` allows it.
- **The pipe** (`\\.\pipe\ActionInna.Link`): only your Windows user can open the link's pipe, and
  only from this PC (the NETWORK group, which a connection over file sharing carries, is denied). A
  pipe name is shared by every user of the PC, so another user could make a pipe of the same name
  first, and a pipe keeps the security of whoever made it. So:
  - the link serves only a pipe its own Windows user owns, and otherwise says it could not open it;
  - the EA serves nothing until the first frame carries the key from `link.key`, which only your
    Windows user can read.
- **The link:** it passes the browser only frames the browser accepts (valid UTF-8 holding one JSON
  object, at most 1 MiB), so one bad frame from an EA can't close the panel's connection.
- **The EA:** it treats every request as untrusted, with the same checks as the chart panel. Every
  write except removing a pending order needs a preview id. Each id works once, within a minute, and
  only on the account (login and server) it was made on. What is sent must be what the preview
  showed: an order or change that would now be another order type (a pending entry the price crossed),
  or a new order with other lots, or with a risk more than 5% higher, is refused.
- **The lines on TradingView's chart:** the panel's script there runs inside TradingView's page,
  where other scripts on that page could fake a drag. A drag only changes what the panel shows: a
  preview's level, or a change card's. Only a line key and a price pass from the page to the panel,
  and prices far from the market are ignored. Nothing reaches MT5 without the trader's Confirm in the
  panel, and Confirm waits until MT5's preview of the latest change, typed or dragged, has been on
  screen for 0.3 seconds: until then it would send the previous preview.
- **Only beside TradingView:** the panel closes itself when another site's tab is in front of its
  window, once it may read TradingView's tabs (it waits for an order on its way).
- **Nothing listens on a network port.**

Out of scope: a program running as your own Windows user. It can do whatever you can, MT5
included.

## How to report

Use **Report a vulnerability** on the repository's **Security** tab (GitHub private vulnerability
reporting). Include:

- the version (EA properties, About), the MT5 build, and whether the account is demo or live, hedging
  or netting;
- the symbol, the inputs you changed, and the steps;
- the lines from `MQL5\Files\ActionInna\log.txt` around the order, and the order or deal ticket;
- for the browser panel, the lines from `%LOCALAPPDATA%\ActionInna\link.log` too, with any account
  login in them removed.

Never include passwords, account numbers or investor logins. The reply comes in the advisory thread.

## Supported versions

Only the latest release gets fixes.
