<#
.SYNOPSIS
    Links this repository into an MT5 data folder, so MetaEditor compiles the sources in place.

.DESCRIPTION
    Creates directory junctions inside <data folder>\MQL5 that point at this repository:

      MQL5\Experts\ActionInna  ->  mql5\Experts\ActionInna
      MQL5\Include\ActionInna  ->  mql5\Include\ActionInna
      MQL5\Scripts\ActionInna  ->  mql5\Scripts\ActionInna
      MQL5\Files\ActionInna    ->  runtime   (the EA's log and the test results)

    It also saves the data folder and the MetaEditor path in mt5.local.json for build.ps1, and keeps a
    copy of your default chart template as "default-before-ActionInna" before you ever press
    "Pin to new charts" in the panel.

.PARAMETER DataFolder
    The MT5 data folder, the one that contains MQL5 (in MT5: File > Open Data Folder). Leave it out to
    pick from the terminals installed under %APPDATA%\MetaQuotes\Terminal.

.PARAMETER MetaEditor
    Full path to metaeditor64.exe, when it is not next to the terminal.

.PARAMETER Unlink
    Removes the junctions. Only the links go; the files in this repository stay.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\link-mt5.ps1
#>
[CmdletBinding()]
param(
    [string]$DataFolder,
    [string]$MetaEditor,
    [switch]$Unlink
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$Repo = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $Repo 'mt5.local.json'
$Links = @(
    @{ Link = 'MQL5\Experts\ActionInna'; Target = 'mql5\Experts\ActionInna' },
    @{ Link = 'MQL5\Include\ActionInna'; Target = 'mql5\Include\ActionInna' },
    @{ Link = 'MQL5\Scripts\ActionInna'; Target = 'mql5\Scripts\ActionInna' },
    @{ Link = 'MQL5\Files\ActionInna';   Target = 'runtime' }
)

# Pick the data folder.
if (-not $DataFolder) {
    if ($Unlink -and (Test-Path -LiteralPath $ConfigPath)) {
        $DataFolder = (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).DataFolder
    }
    else {
        $terminals = @(Get-Terminals)
        if ($terminals.Count -eq 0) {
            throw "No MT5 data folder found under $env:APPDATA\MetaQuotes\Terminal. Pass -DataFolder (in MT5: File > Open Data Folder)."
        }
        if ($terminals.Count -eq 1) {
            $DataFolder = $terminals[0].DataFolder
        }
        else {
            Write-Host 'MT5 terminals on this PC:'
            for ($i = 0; $i -lt $terminals.Count; $i++) {
                Write-Host ('  [{0}] {1}' -f ($i + 1), $terminals[$i].Install)
                Write-Host ('       {0}' -f $terminals[$i].DataFolder)
            }
            $choice = Read-Host 'Number of the terminal to link'
            $index = 0
            if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $terminals.Count) {
                throw 'No such terminal.'
            }
            $DataFolder = $terminals[$index - 1].DataFolder
        }
    }
}
$DataFolder = (Resolve-Path -LiteralPath $DataFolder).Path
$Mql5 = Join-Path $DataFolder 'MQL5'
if (-not (Test-Path -LiteralPath $Mql5)) {
    throw "$DataFolder has no MQL5 folder. Use the data folder (in MT5: File > Open Data Folder)."
}

if ($Unlink) {
    foreach ($l in $Links) {
        $path = Join-Path $DataFolder $l.Link
        if (Test-Junction $path) {
            Remove-Junction $path
            Write-Host "Removed link $path"
        }
    }
    return
}

# Junctions.
New-Item -ItemType Directory -Force -Path (Join-Path $Repo 'runtime') | Out-Null
foreach ($l in $Links) {
    $path = Join-Path $DataFolder $l.Link
    $target = Join-Path $Repo $l.Target
    if (Test-Junction $path) {
        Remove-Junction $path
    }
    elseif (Test-Path -LiteralPath $path) {
        throw "$path is a real folder. Move it somewhere else, then run this script again."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    New-Item -ItemType Junction -Path $path -Value $target | Out-Null
    Write-Host "Linked $path -> $target"
}

# A copy of the default chart template, before "Pin to new charts" replaces it.
$templateDirs = @((Join-Path $Mql5 'Profiles\Templates'), (Join-Path $DataFolder 'Profiles\Templates')) |
    Where-Object { Test-Path -LiteralPath $_ }
foreach ($dir in $templateDirs) {
    $default = Join-Path $dir 'default.tpl'
    $backup = Join-Path $dir 'default-before-ActionInna.tpl'
    if ((Test-Path -LiteralPath $default) -and -not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $default -Destination $backup
        Write-Host "Kept a copy of your default template: $backup"
    }
}

# MetaEditor, for build.ps1.
if (-not $MetaEditor) { $MetaEditor = Find-MetaEditor $DataFolder }
if ($MetaEditor -and -not (Test-Path -LiteralPath $MetaEditor)) {
    throw "$MetaEditor does not exist."
}
if (-not $MetaEditor) {
    Write-Warning 'metaeditor64.exe was not found. Compile with F7 in MetaEditor, or run this script again with -MetaEditor "C:\...\metaeditor64.exe".'
}

[pscustomobject]@{ DataFolder = $DataFolder; MetaEditor = $MetaEditor } |
    ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
Write-Host "Saved $ConfigPath"
Write-Host 'Next: powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Tests'
