@echo off
setlocal EnableExtensions
title chichi77 KeyKey Installer

set "InstallerSource=%~dp0"
set "InstallerStage=%TEMP%\chichi77-keykey-install-%RANDOM%-%RANDOM%-%RANDOM%"

echo Preparing chichi77 KeyKey installer...
echo Source: "%InstallerSource%"
echo Local staging: "%InstallerStage%"

if exist "%InstallerStage%" (
    echo Installation failed: the temporary directory already exists.
    echo Please run Install.cmd again.
    pause
    exit /b 10
)

mkdir "%InstallerStage%" >nul 2>&1
if errorlevel 1 (
    echo Installation failed: could not create the local temporary directory.
    pause
    exit /b 11
)

"%SystemRoot%\System32\xcopy.exe" "%InstallerSource%*" "%InstallerStage%\" /E /I /H /Y /Q >nul
if errorlevel 1 (
    echo Installation failed while copying the package from:
    echo "%InstallerSource%"
    rmdir /s /q "%InstallerStage%" >nul 2>&1
    pause
    exit /b 12
)

echo Requesting administrator permission...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%InstallerStage%\Install.ps1"
set "InstallExitCode=%ERRORLEVEL%"
rmdir /s /q "%InstallerStage%" >nul 2>&1

if "%InstallExitCode%"=="3010" (
    echo Installation completed. Restart Windows to finish file cleanup.
) else if not "%InstallExitCode%"=="0" (
    echo.
    echo Installation failed with exit code %InstallExitCode%.
    echo Run Payload\KeyKeyDeployment.exe inspect to view installation metadata.
)
if "%InstallExitCode%"=="0" (
    echo Add chichi77 KeyKey in Windows Settings ^> Time and language ^> Language options ^> Add a keyboard.
    echo After upgrading, sign out and back in to load the new input method.
)
pause
exit /b %InstallExitCode%
