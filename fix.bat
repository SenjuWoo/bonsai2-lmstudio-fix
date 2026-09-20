@echo off
title Bonsai 2 fix for LM Studio
setlocal
set "PS=powershell -NoProfile -ExecutionPolicy Bypass"
set "URL=https://github.com/SenjuWoo/bonsai2-lmstudio-fix/releases/download/v1.0.0/install.ps1"
set "F=%TEMP%\bonsai2-lmstudio-fix.ps1"

echo.
echo   Bonsai 2 / PrismML fix for LM Studio
echo   ===================================
echo   Patches LM Studio's engine so Bonsai 2 (PTQ1_0 / PQ2_0) models load.
echo   Downloads PrismML's prebuilt binaries; backs up your engine files first.
echo.

%PS% -Command "iwr '%URL%' -OutFile '%F%'"
if not exist "%F%" (
  echo   Download failed - check your internet connection and try again.
  echo.
  pause
  exit /b 1
)
%PS% -File "%F%"
del "%F%" >nul 2>&1
echo.
pause
