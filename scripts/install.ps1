<#
.SYNOPSIS
    Installs ActionInna from this folder for this Windows user. install.bat runs it.

.DESCRIPTION
    Needs MetaTrader 5 desktop, opened at least once, and no administrator rights:

      1. Compiles the EA with the MetaEditor that comes with MT5 (scripts\build.ps1).
      2. Builds the link, build\ActionInnaLink.exe (scripts\build-link.ps1).
      3. Runs ActionInnaLink.exe --install --dev. It copies ActionInna.ex5 into every MT5 it finds
         (a terminal linked by link-mt5.ps1 is left as it is), registers the link for Chrome, Edge,
         Brave and Chromium, and lets the side panel loaded unpacked from extension\ start it.

    The link runs from build\ and the side panel from extension\, so keep this folder where it is.
    Run it again after an update; close the side panel first, as the browser keeps the link's file
    open. uninstall.bat removes the link's registration.

.PARAMETER MetaEditor
    Full path to metaeditor64.exe, when it is not next to MT5.

.PARAMETER Mt5
    The one MT5 to install into, by its data folder (in MT5: File > Open Data Folder). Leave it out
    to install into every MT5 under %APPDATA%\MetaQuotes\Terminal. A portable terminal needs it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install.ps1
#>
[CmdletBinding()]
param(
    [string]$MetaEditor,
    [string]$Mt5
)

$ErrorActionPreference = 'Stop'
# Whoever double-clicked install.bat needs the message, not PowerShell's line and column of it.
trap { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
. (Join-Path $PSScriptRoot '_common.ps1')

$Repo = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Repo 'build'

if ($Mt5) {
    $folders = @((Resolve-Path -LiteralPath $Mt5).Path)
    if (-not (Test-Path -LiteralPath (Join-Path $folders[0] 'MQL5'))) {
        throw "$Mt5 has no MQL5 folder. Use the data folder (in MT5: File > Open Data Folder)."
    }
}
else {
    $folders = @(Get-Terminals | ForEach-Object { $_.DataFolder })
}
if ($folders.Count -eq 0) {
    throw 'No MetaTrader 5 found. Install MT5 desktop for Windows, open it once, then run install.bat again.'
}
if (-not $MetaEditor) {
    $MetaEditor = Find-MetaEditor $folders
}
if (-not $MetaEditor) {
    throw 'metaeditor64.exe was not found next to MT5. Run install.bat -MetaEditor "C:\...\metaeditor64.exe".'
}

Write-Host '[1/3] Compiling the EA'
& (Join-Path $PSScriptRoot 'build.ps1') -MetaEditor $MetaEditor

Write-Host ''
Write-Host '[2/3] Building the link'
& (Join-Path $PSScriptRoot 'build-link.ps1')
# --install copies the EA into MT5 from next to the link.
Copy-Item -LiteralPath (Join-Path $Repo 'mql5\Experts\ActionInna\ActionInna.ex5') -Destination $BuildDir -Force

Write-Host ''
Write-Host '[3/3] Installing'
$linkArgs = @('--install', '--dev', '--quiet')
if ($Mt5) { $linkArgs += @('--mt5', $folders[0]) }
& (Join-Path $BuildDir 'ActionInnaLink.exe') $linkArgs
if ($LASTEXITCODE -ne 0) { throw 'The link did not install (see the lines above).' }

Write-Host ''
Write-Host 'Step 2, until the side panel is in the Chrome Web Store: open chrome://extensions (in Edge'
Write-Host 'or Brave too), turn on Developer mode, press Load unpacked, and pick this folder:'
Write-Host "  $(Join-Path $Repo 'extension')"
Write-Host ''
Write-Host 'Keep this folder: the link and the side panel run from it. To remove the link: uninstall.bat.'
