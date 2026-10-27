@echo off
rem Double-click to remove what install.bat set up for the link: its browser registration, its key
rem and its settings. ActionInna.ex5 stays in MT5 and the side panel in the browser: remove them there.
set "link=%~dp0build\ActionInnaLink.exe"
if not exist "%link%" goto missing
"%link%" --uninstall --quiet
set "code=%errorlevel%"
pause
exit /b %code%

:missing
echo Nothing to remove: "%link%" is not there.
pause
exit /b 1
