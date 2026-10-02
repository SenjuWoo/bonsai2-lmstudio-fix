@echo off
setlocal
title Bonsai 2 runtime for LM Studio
echo Bonsai 2 / PrismML runtime for LM Studio
echo Unload models and close LM Studio before installing.
if exist "%~dp0install.ps1" goto local
set "BONSAI_INSTALLER=%TEMP%\bonsai2-lmstudio-fix-%RANDOM%-%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://github.com/SenjuWoo/bonsai2-lmstudio-fix/releases/download/v1.1.0/install.ps1' -UseBasicParsing -OutFile $env:BONSAI_INSTALLER"
if errorlevel 1 goto download_failed
powershell -NoProfile -ExecutionPolicy Bypass -File "%BONSAI_INSTALLER%" %*
set "RESULT=%ERRORLEVEL%"
goto cleanup
:download_failed
set "RESULT=1"
goto cleanup
:local
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "RESULT=%ERRORLEVEL%"
goto finish
:cleanup
if exist "%BONSAI_INSTALLER%" del "%BONSAI_INSTALLER%" >nul 2>&1
:finish
echo.
if not "%RESULT%"=="0" echo Installation failed. Read the error above.
if not defined BONSAI_NO_PAUSE pause
exit /b %RESULT%
