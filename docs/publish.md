# Publishing ActionInna

How a release gets to traders: the side panel through the Chrome Web Store, the link and the EA
as a download on GitHub. The scripts only build and pack. Every step that puts something online is
done by hand, by the owner of the store and repository accounts.

## 1. Build, check and pack

1. `scripts\build.ps1 -Tests`: 0 errors, 0 warnings for both programs.
2. `scripts\build-link.ps1`.
3. The tests (CONTRIBUTING.md), and README section 10's checklist on a demo account, through the
   side panel as well as on the chart.
4. Give the release its version: `"version"` in `extension/manifest.json`, and a section for it
   with the date in `CHANGELOG.md`. Keep one version for both downloads. The store refuses an
   upload whose version isn't higher than the last one.
5. `scripts\release.ps1` packs `build\release`:
   - `ActionInna-panel-<version>.zip`: the side panel for the stores, without `dev\` and without
     the manifest's `"key"`;
   - `ActionInna-<version>-windows.zip`: `ActionInnaLink.exe` and `ActionInna.ex5`, with the README
     and the licence.

## 2. Chrome Web Store, the first time

1. Register as a developer in the Chrome Web Store Developer Dashboard. There is a one-time fee.
2. **New item:** upload `ActionInna-panel-<version>.zip`. The dashboard gives the item its ID
   (32 letters) straight away.
3. **Before you submit,** add that ID to `ExtensionIds` in `link/Installer.cs`, next to the
   development ID. Then run `scripts\build-link.ps1` and `scripts\release.ps1` again. The link
   answers only the extension IDs it was installed with, so without this the store's panel can't
   reach it.
4. **Store listing:**
   - Summary: the manifest's description ("Risk-sized MetaTrader 5 orders in a side panel next to
     TradingView, sent through your own MT5.").
   - Description: what the panel does (README section 4), and what it needs: MT5 desktop on Windows
     with ActionInna on a chart, and the link from the GitHub download. Say that nothing leaves the
     PC.
   - At least one screenshot, 1280x800 or 640x400: TradingView with the panel beside it, on a demo
     account, with no account number showing.
   - The 128 px icon is in the zip (`icons/icon128.png`).
5. **Privacy:**
   - Single purpose: "Size MetaTrader 5 orders by risk and send them through the trader's own MT5,
     from a side panel."
   - Why each permission:
     - `sidePanel`: the panel itself.
     - `nativeMessaging`: talking to the ActionInna link on the trader's PC, which passes the
       panel's requests to MT5 and back.
     - `storage`: the trader's choices (risk, SL/TP modes, last symbol), kept on this PC.
     - `scripting`: putting the extension's own two scripts (`tv/page.js`, `tv/bridge.js`) into
       the TradingView tab, to draw the order's lines on its chart and report a dragged line.
     - `https://*.tradingview.com/*`, optional: asked with one click the first time the panel
       opens. The panel reads the address and title of the TradingView tab in front, to tell its
       symbol, and draws its lines there. It reads nothing else.
   - Remote code: none. The scripts put into TradingView's tab are files in the package.
   - Data use: answer from [privacy.md](privacy.md). Account and trade data come from the trader's
     own MT5, are shown in the panel and are sent nowhere. Choices stay in the browser's storage.
   - Privacy policy: the address of `docs/privacy.md` on GitHub, once it is on `main`.
6. Submit for review.

The development ID comes from the `"key"` in `extension/manifest.json`, which was made on this PC.
To give the unpacked panel the store's ID instead, copy the item's public key from the dashboard's
Package tab into `"key"`. The development ID can then leave `ExtensionIds`.

Edge Add-ons takes the same zip. It gives the item an ID of its own, which goes into
`ExtensionIds` too.

## 3. The Windows download

1. A GitHub release for the version, with `ActionInna-<version>-windows.zip` attached, and the
   version's section of `CHANGELOG.md` as its notes.
2. Setting up, for the notes:
   1. Install the side panel from the Chrome Web Store.
   2. Unzip the download, and run `ActionInnaLink.exe --install`. It registers the link for this
      Windows user, and copies `ActionInna.ex5` into the MT5 terminals it finds.
   3. In MT5, put ActionInna on one chart, with Algo Trading on.
3. The link isn't code-signed. Windows SmartScreen warns the first time it runs: **More info**, then
   **Run anyway**. Say so in the notes.

## Later releases

Raise the version, then pack and upload the new panel zip. A new Windows download is needed only
when `link/` or the EA changed.
