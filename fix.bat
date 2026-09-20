@echo off
title Bonsai 2 fix for LM Studio
set "F=%TEMP%\bonsai2-lmstudio-fix.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/SenjuWoo/bonsai2-lmstudio-fix/main/install.ps1 -OutFile '%F%'"
if not exist "%F%" (echo Download failed - check your internet connection. & pause & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%F%"
del "%F%" >nul 2>&1
echo.
pause
