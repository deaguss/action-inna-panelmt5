<#
.SYNOPSIS
    Compiles ActionInna with MetaEditor and writes the compile logs to build\.

.DESCRIPTION
    Compiles the sources where they are, in mql5\ (the .ex5 lands next to its .mq5), so it needs no
    link into MT5. MetaEditor is the one given with -MetaEditor, else the one saved by link-mt5.ps1,
    else the first one found next to an installed MT5. MetaEditor's exit code is not reliable, so
    the result is read from the "Result: N errors" line of its log. Each log is copied to
    build\<name>.txt as UTF-8.

.PARAMETER Tests
    Also compiles the ActionInnaTests script.

.PARAMETER MetaEditor
    Full path to metaeditor64.exe.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Tests
#>
[CmdletBinding()]
param([switch]$Tests, [string]$MetaEditor)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$Repo = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $Repo 'mt5.local.json'
if (-not $MetaEditor -and (Test-Path -LiteralPath $ConfigPath)) {
    $MetaEditor = (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).MetaEditor
}
if (-not $MetaEditor) {
    $MetaEditor = Find-MetaEditor @(Get-Terminals | ForEach-Object { $_.DataFolder })
}
if (-not $MetaEditor -or -not (Test-Path -LiteralPath $MetaEditor)) {
    throw 'metaeditor64.exe was not found. Install MetaTrader 5 and open it once, or pass -MetaEditor "C:\...\metaeditor64.exe".'
}
# MetaEditor resolves <ActionInna\...> includes against <this folder>\Include.
$Mql5 = Join-Path $Repo 'mql5'
$BuildDir = Join-Path $Repo 'build'
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$Sources = @('Experts\ActionInna\ActionInna.mq5')
if ($Tests) { $Sources += 'Scripts\ActionInna\ActionInnaTests.mq5' }

$failed = 0
foreach ($rel in $Sources) {
    $src = Join-Path $Mql5 $rel
    if (-not (Test-Path -LiteralPath $src)) { throw "$src is missing." }
    $name = [IO.Path]::GetFileNameWithoutExtension($src)
    $log = [IO.Path]::ChangeExtension($src, '.log')
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

    $arguments = '/compile:"' + $src + '" /include:"' + $Mql5 + '" /log'
    $proc = Start-Process -FilePath $MetaEditor -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden

    if (-not (Test-Path -LiteralPath $log)) {
        Write-Warning "MetaEditor wrote no log for $rel (exit code $($proc.ExitCode))."
        $failed++
        continue
    }
    $text = Read-TextAuto $log
    $out = Join-Path $BuildDir ($name + '.txt')
    Set-Content -LiteralPath $out -Value $text -Encoding UTF8

    $lines = $text -split "`r?`n"
    $result = $lines | Where-Object { $_ -match 'Result:' } | Select-Object -Last 1
    if (-not $result) { $result = 'no result line (see the log)' }
    Write-Host "$name : $result"
    $lines | Where-Object { $_ -match '\b(error|warning)\b' -and $_ -notmatch 'Result:' } | ForEach-Object { Write-Host "  $_" }
    if ($result -match '(\d+)\s+error') {
        if ([int]$Matches[1] -gt 0) { $failed++ }
    }
    else {
        $failed++
    }
}

# A throw, not exit 1: install.ps1 calls this script and stops on it. Run on its own, it still exits with 1.
if ($failed -gt 0) { throw "Build failed. Logs: $BuildDir" }
Write-Host 'Build OK. The .ex5 files are next to their sources in mql5\.'
