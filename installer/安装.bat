@echo off
cd /d "%~dp0"
chcp 65001 >nul
echo Claude Code Prompt Override - installer v2 (2026-10-30)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
