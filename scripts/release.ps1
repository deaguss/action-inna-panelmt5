<#
.SYNOPSIS
    Packs a release into build\release: the side panel for the browser stores, and the link with the
    EA for Windows.

.DESCRIPTION
    Run scripts\build.ps1 and scripts\build-link.ps1 first. The version is the side panel's, from
    extension\manifest.json.

      ActionInna-panel-<version>.zip    for the Chrome Web Store (and Edge Add-ons): extension\
                                        without dev\ (the stand-in for the link), and with no "key"
                                        in the manifest (it only pins the development ID)
      ActionInna-<version>-windows.zip  ActionInnaLink.exe and ActionInna.ex5 side by side, with
                                        README.md and LICENSE. ActionInnaLink.exe --install copies
                                        the EA into MT5 from next to itself.

    Nothing is uploaded or published.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\release.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Ext = Join-Path $Repo 'extension'
$OutDir = Join-Path $Repo 'build\release'
Add-Type -AssemblyName System.IO.Compression

$link = Join-Path $Repo 'build\ActionInnaLink.exe'
$ex5 = Join-Path $Repo 'mql5\Experts\ActionInna\ActionInna.ex5'
foreach ($f in @($link, $ex5)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "$f is missing: run scripts\build.ps1 and scripts\build-link.ps1 first." }
}

# A program older than its newest source was built before the last change.
function Assert-Newer([string]$Built, [string]$Sources) {
    $newest = Get-ChildItem -Path $Sources -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest -and $newest.LastWriteTime -gt (Get-Item -LiteralPath $Built).LastWriteTime) {
        throw "$Built is older than $($newest.FullName): build it again first."
    }
}
Assert-Newer $link (Join-Path $Repo 'link')
Assert-Newer $ex5 (Join-Path $Repo 'mql5\Include\ActionInna')
Assert-Newer $ex5 (Join-Path $Repo 'mql5\Experts\ActionInna\ActionInna.mq5')

$manifestPath = Join-Path $Ext 'manifest.json'
$manifestText = [IO.File]::ReadAllText($manifestPath)
$version = (ConvertFrom-Json $manifestText).version
if (-not $version) { throw 'extension\manifest.json has no version.' }
$storeManifest = [Text.RegularExpressions.Regex]::Replace($manifestText, '(?m)^\s*"key"\s*:\s*"[^"]*",\s*\r?\n', '')
if ((ConvertFrom-Json $storeManifest).PSObject.Properties.Name -contains 'key') {
    throw 'Could not take the key out of the manifest.'
}

# Entries are named with forward slashes, which every unzip program and the stores read.
function New-Zip([string]$Path, [object[]]$Entries) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($e in $Entries) {
            $entry = $zip.CreateEntry($e.Name, [IO.Compression.CompressionLevel]::Optimal)
            $out = $entry.Open()
            try { $out.Write($e.Bytes, 0, $e.Bytes.Length) } finally { $out.Dispose() }
        }
    } finally {
        $zip.Dispose()
        $stream.Dispose()
    }
}

function Get-Entry([string]$Name, [string]$File) {
    return [pscustomobject]@{ Name = $Name; Bytes = [IO.File]::ReadAllBytes($File) }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$panel = New-Object System.Collections.ArrayList
$devDir = Join-Path $Ext 'dev'
foreach ($f in Get-ChildItem -Path $Ext -Recurse -File) {
    if ($f.FullName.StartsWith($devDir + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
    $name = $f.FullName.Substring($Ext.Length + 1).Replace('\', '/')
    if ($name -eq 'manifest.json') {
        [void]$panel.Add([pscustomobject]@{ Name = $name; Bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($storeManifest) })
    } else {
        [void]$panel.Add((Get-Entry $name $f.FullName))
    }
}
$panelZip = Join-Path $OutDir ("ActionInna-panel-$version.zip")
New-Zip $panelZip $panel.ToArray()

$windowsZip = Join-Path $OutDir ("ActionInna-$version-windows.zip")
New-Zip $windowsZip @(
    (Get-Entry 'ActionInnaLink.exe' $link),
    (Get-Entry 'ActionInna.ex5' $ex5),
    (Get-Entry 'README.md' (Join-Path $Repo 'README.md')),
    (Get-Entry 'LICENSE' (Join-Path $Repo 'LICENSE'))
)

foreach ($z in @($panelZip, $windowsZip)) {
    Write-Host ("{0} ({1:N0} bytes)" -f $z, (Get-Item -LiteralPath $z).Length)
}
Write-Host "Panel: $($panel.Count) files, without dev\ and without the manifest's key."
Write-Host 'Next: docs\publish.md. Nothing was uploaded.'
