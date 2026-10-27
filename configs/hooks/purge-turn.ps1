# UserPromptSubmit hook：每轮把口径注入一次
# 放在 ~/.claude/hooks/purge-turn.ps1
#
# 注意：Windows 上 hook 的 command 必须是 `powershell -File xxx.ps1` 这种形式。
# 写成 .cmd 或 `cmd /c xxx.cmd` 不会触发（实测）。

$ErrorActionPreference = "SilentlyContinue"

# 触发日志，用来验证 hook 是否真的在跑；不需要可以删掉这一行
Add-Content -Path "$env:USERPROFILE\.claude\purge-hook.log" -Value (Get-Date -Format "HH:mm:ss")

# stdout 会被 Claude Code 当成上下文注入
Get-Content "$env:USERPROFILE\.claude\purge-turn-context.md" -Raw -Encoding UTF8
