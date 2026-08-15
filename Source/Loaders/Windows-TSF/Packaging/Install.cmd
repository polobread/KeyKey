@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "InstallExitCode=%ERRORLEVEL%"
if not "%InstallExitCode%"=="0" echo Installation failed with exit code %InstallExitCode%.
pause
exit /b %InstallExitCode%
