<#
.SYNOPSIS
    Compiles ActionInna with MetaEditor and writes the compile logs to build\.

.DESCRIPTION
    Uses the data folder and MetaEditor saved by link-mt5.ps1. MetaEditor's exit code is not
    reliable, so the result is read from the "Result: N errors" line of its log. Each log is
    copied to build\<name>.txt as UTF-8.

.PARAMETER Tests
    Also compiles the ActionInnaTests script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Tests
#>
[CmdletBinding()]
param([switch]$Tests)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$Repo = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $Repo 'mt5.local.json'
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw 'Run scripts\link-mt5.ps1 first.' }
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $Config.MetaEditor -or -not (Test-Path -LiteralPath $Config.MetaEditor)) {
    throw 'metaeditor64.exe is unknown. Run scripts\link-mt5.ps1 -MetaEditor "C:\...\metaeditor64.exe".'
}
$Mql5 = Join-Path $Config.DataFolder 'MQL5'
$BuildDir = Join-Path $Repo 'build'
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$Sources = @('Experts\ActionInna\ActionInna.mq5')
if ($Tests) { $Sources += 'Scripts\ActionInna\ActionInnaTests.mq5' }

$failed = 0
foreach ($rel in $Sources) {
    $src = Join-Path $Mql5 $rel
    if (-not (Test-Path -LiteralPath $src)) { throw "$src is missing. Run scripts\link-mt5.ps1 first." }
    $name = [IO.Path]::GetFileNameWithoutExtension($src)
    $log = [IO.Path]::ChangeExtension($src, '.log')
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

    $arguments = '/compile:"' + $src + '" /include:"' + $Mql5 + '" /log'
    $proc = Start-Process -FilePath $Config.MetaEditor -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden

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

if ($failed -gt 0) {
    Write-Host "Build failed. Logs: $BuildDir"
    exit 1
}
Write-Host "Build OK. In MT5: Navigator > Expert Advisors > ActionInna (press Refresh if it is not there yet)."
