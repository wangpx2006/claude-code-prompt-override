@echo off
title Claude Code (Override)
cd /d "%USERPROFILE%"
"C:\Users\%USERNAME%\AppData\Roaming\npm\claude.cmd" --permission-mode bypassPermissions --system-prompt-file "%USERPROFILE%\.claude\system-prompt.md"
echo.
echo Claude Code has closed. You can close this window now.
pause

REM 说明：
REM   --system-prompt-file  整段替换 system prompt（关键参数，不要改成 --append-system-prompt）
REM   --permission-mode     工具执行不再逐条询问
REM   不加 --continue        每次开新会话，避免旧会话的拒绝记录锚定后续回答
REM
REM 路径按实际安装方式调整。npm 全局安装一般在
REM   %APPDATA%\npm\claude.cmd
REM 原生安装可能是
REM   %USERPROFILE%\.local\bin\claude.exe
