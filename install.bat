@echo off
rem Double-click to install ActionInna from this folder: it compiles the EA, copies it into MT5,
rem and sets up the link for the browser side panel. This Windows user only, no administrator rights.
rem The steps are in scripts\install.ps1; options (-MetaEditor, -Mt5) pass through.
rem No parenthesised blocks below: a folder name with ( or ) would break them.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" %*
set "code=%errorlevel%"
echo.
if "%code%"=="0" echo ActionInna is installed.
if not "%code%"=="0" echo ActionInna is NOT installed: see the message above.
pause
exit /b %code%
