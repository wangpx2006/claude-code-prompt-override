@echo off
title Claude Code (Override)
cd /d "%USERPROFILE%"
"%APPDATA%\npm\claude.cmd" --permission-mode bypassPermissions --system-prompt-file "%USERPROFILE%\.claude\system-prompt.md"
echo.
echo Claude Code has closed. You can close this window now.
pause

REM 说明：
REM   --system-prompt-file  整段替换 system prompt（关键参数，不要改成 --append-system-prompt）
REM   --permission-mode     工具执行不再逐条询问
REM   不加 --continue        每次开新会话，避免旧会话的拒绝记录锚定后续回答
REM
REM 路径按实际安装方式调整。npm 全局安装用 %APPDATA%\npm\claude.cmd
REM （不要拼 C:\Users\%USERNAME%\...，用户名带空格或换机器时会断）。
REM 原生安装可能是 %USERPROFILE%\.local\bin\claude.exe
REM 新版 npm 包的真正二进制在 node_modules\@anthropic-ai\claude-code\bin\claude.exe，
REM claude.cmd 只是转发 shim，用法不变。
