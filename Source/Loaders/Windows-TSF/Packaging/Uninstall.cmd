@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
set "UninstallExitCode=%ERRORLEVEL%"
if not "%UninstallExitCode%"=="0" echo Uninstallation failed with exit code %UninstallExitCode%.
pause
exit /b %UninstallExitCode%
