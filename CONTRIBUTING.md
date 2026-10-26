# Contributing to ActionInna

Thanks for helping. ActionInna sends real orders, so every change is held to one rule: **it must
never send an order the trader did not preview and confirm.** Keep that in mind in review too.

## Set up

You need MetaTrader 5 desktop for Windows (it includes MetaEditor) and a demo account.

```powershell
git clone https://github.com/deaguss/action-inna-panelmt5.git
cd action-inna-panelmt5
powershell -ExecutionPolicy Bypass -File scripts\link-mt5.ps1
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Tests
```

`link-mt5.ps1` links the repository into your MT5 data folder with directory junctions, so MetaEditor
compiles the files in place. `build.ps1` compiles and writes the logs to `build\`. Remove the links with
`scripts\link-mt5.ps1 -Unlink`; never with `Remove-Item -Recurse`, which follows a junction in Windows
PowerShell 5.1 and deletes the files it points to.

A recompiled EA keeps running its old code on charts it is already on. Restart MT5, or drag the EA
onto the chart again, before testing a change.

## Test

1. `scripts\build.ps1 -Tests` must report **0 errors, 0 warnings** for both programs.
2. Drag **Scripts > ActionInna > ActionInnaTests** onto any chart and press OK. It runs the worked
   examples and about 124,000 generated scenarios (seed and rounds are inputs; the same seed replays
   the same scenarios). Every suite must say "all passed". The full report is written to
   `MQL5\Files\ActionInna\test-results.txt` (`runtime\test-results.txt` with the linked set-up).
   Before you share it, check it holds nothing about your account.
3. `bash tests/native/run.sh` (Git Bash, Node.js, g++) must end with "native tests: all passed". It
   runs the same tests and the drag-and-confirm scenarios without MT5 (README section 11).
4. For a change to the link: `scripts\build-link.ps1`, then `node tests/link/run.js` must report 0
   failed.
5. For a change to the side panel: `node tests/extension/run.mjs` must report 0 failed. Try what you
   changed in a browser tab with `node tests/extension/serve.js` (README section 11), at the side
   panel's width (320 to 400 px), in both themes.
6. For anything the panel shows or sends, test it on a **demo account** and say in the pull request
   what you clicked and what happened. The checklist in README section 10 covers the main flows.

New logic in `RiskCalc.mqh`, `SymbolSpec.mqh`, `Memory.mqh`, `Hotkeys.mqh` or `Util.mqh` needs a worked
example in `ActionInnaTests.mq5` and, where it has rules that hold for every input, a scenario suite in
`Scenarios.mqh`.

## Code style

- MQL5 sources are ASCII only (CI checks it). Build any other character with `ShortToString`.
- Three-space indents, as MetaEditor formats them. Free functions start with `Ai`, classes with `CAi`,
  chart objects with the `AINNA_` prefix.
- Never copy a struct that holds a string or an array: pass it by reference.
- Guard every division and array index. A runtime error unloads the EA without `OnDeinit`, which
  leaves the chart settings it changed (such as the hidden One-Click panel) behind.
- A comment says why, not what. Keep a comment only when the code cannot say it.
- Colours: every text pair 4.5:1, every control edge 3:1, in both themes. Record new colours in
  `DESIGN.md` with their measured contrast.

## Pull requests

- One change per pull request, with an entry under "Unreleased" in `CHANGELOG.md`.
- Update the README when behaviour, inputs or hotkeys change.
- Fill in the pull request template, including the test results line.

## Reporting

Bugs and ideas go to the issue tracker. Anything that could send an unexpected order, or the wrong
volume, SL or TP, is a security issue: follow [SECURITY.md](SECURITY.md) instead of opening a public
issue.
