@echo off
title Bonsai 2 fix for LM Studio
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/SenjuWoo/bonsai2-lmstudio-fix/main/install.ps1 | iex"
echo.
pause
