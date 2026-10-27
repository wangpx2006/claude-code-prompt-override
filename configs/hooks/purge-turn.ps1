# UserPromptSubmit hook：每轮把口径注入一次
# 放在 ~/.claude/hooks/purge-turn.ps1
#
# 本文件必须存成 UTF-8 with BOM。PowerShell 5.1 读无 BOM 的 .ps1 时按 ANSI 解析，
# 中文注释的字节会把语法拆坏，表现是脚本零输出、也不报错，特别难查。
#
# 注意：Windows 上 hook 的 command 必须是 `powershell -File xxx.ps1` 这种形式。
# 写成 .cmd 或 `cmd /c xxx.cmd` 不会触发（实测）。

# 强制 stdout 走 UTF-8。不设的话 PowerShell 5.1 按系统代码页（中文 Windows 是 936）
# 写出，Claude Code 按 UTF-8 解码，中文全变乱码 —— 等于白注入还占上下文。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "SilentlyContinue"

# 触发日志，用来验证 hook 是否真的在跑；超过 200KB 自动清空，不无限长
$log = "$env:USERPROFILE\.claude\purge-hook.log"
if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Clear-Content $log }
Add-Content -Path $log -Value (Get-Date -Format "HH:mm:ss")

# stdout 会被 Claude Code 当成上下文注入
Get-Content "$env:USERPROFILE\.claude\purge-turn-context.md" -Raw -Encoding UTF8
