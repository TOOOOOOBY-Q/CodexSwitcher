@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERRORLEVEL="
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\core\Switcher.ps1" -Mode ThirdParty -LegacyDeepSeek
set "RC=%ERRORLEVEL%"
if defined CODEX_SWITCHER_NO_PAUSE goto :done
pause
:done
endlocal & exit /b %RC%
