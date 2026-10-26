<#
.SYNOPSIS
    Builds the ActionInna link, build\ActionInnaLink.exe.

.DESCRIPTION
    Compiles link\*.cs with the C# compiler that comes with .NET Framework 4.x in Windows 10 and 11,
    so nothing has to be installed. For the development set-up, then run once:

      build\ActionInnaLink.exe --install --dev

    It registers the link for Chrome, Edge, Brave and Chromium (this Windows user only) and points
    them at build\, so a rebuild needs no new install. Close the browser panel before rebuilding:
    Chrome keeps the running link's file open.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-link.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Repo 'build'
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "$csc is missing (.NET Framework 4.x)." }
$exe = Join-Path $BuildDir 'ActionInnaLink.exe'
$sources = Join-Path $Repo 'link\*.cs'
& $csc /nologo /target:exe /optimize+ /r:System.Core.dll /r:System.Web.Extensions.dll "/out:$exe" $sources
if ($LASTEXITCODE -ne 0) { throw 'The link did not compile (is the browser panel still open? Close it, then build again).' }
Write-Host "Built $exe"
