@echo off
chcp 65001 >nul
title 安装 Claude Code 提示词覆盖
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 (
    echo.
    echo 安装过程中出错了，把上面的红字截图发给我。
    pause
)
