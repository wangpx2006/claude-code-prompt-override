@echo off
chcp 65001 >nul
title 卸载 Claude Code 提示词覆盖
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall
if errorlevel 1 (
    echo.
    echo 卸载过程中出错了，把上面的红字截图发给我。
    pause
)
