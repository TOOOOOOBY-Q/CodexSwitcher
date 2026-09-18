@echo off
setlocal EnableExtensions DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verify-Desktop-Lifecycle.ps1" -PauseForModelChecks
set "RC=%ERRORLEVEL%"
pause
endlocal & exit /b %RC%
