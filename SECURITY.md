# Security policy

ActionInna places orders on a real trading account, so some bugs cost money. Report those privately.

## What to report privately

- An order sent without a preview and a confirm (with one-click trading off).
- An order sent with a different side, type, volume, entry, SL or TP than the preview showed.
- A lot size that risks more than the risk you set.
- Anything written outside MT5's own file folders, or any network access.

Other bugs, including wrong numbers on the panel that never reach an order, go to the public issue
tracker.

## How to report

Use **Report a vulnerability** on the repository's **Security** tab (GitHub private vulnerability
reporting). Include:

- the version (EA properties, About), the MT5 build, and whether the account is demo or live, hedging
  or netting;
- the symbol, the inputs you changed, and the steps;
- the lines from `MQL5\Files\ActionInna\log.txt` around the order, and the order or deal ticket.

Never include passwords, account numbers or investor logins. The reply comes in the advisory thread.

## Supported versions

Only the latest release gets fixes.
