#Requires -Version 5.1
<#
  Claude Code 提示词覆盖 · 一键安装 / 卸载
  用法（由 安装.bat / 卸载.bat 调用，一般不用手敲）：
    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Here         = Split-Path -Parent $MyInvocation.MyCommand.Path
$FilesDir     = Join-Path $Here 'files'
$ClaudeDir    = Join-Path $env:USERPROFILE '.claude'
$HooksDir     = Join-Path $ClaudeDir 'hooks'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'
$PromptPath   = Join-Path $ClaudeDir 'system-prompt.md'
$HookPath     = Join-Path $HooksDir  'purge-turn.ps1'
$ContextPath  = Join-Path $ClaudeDir 'purge-turn-context.md'
$Stamp        = Get-Date -Format 'yyyyMMdd-HHmmss'

# 桌面路径：正常情况下由系统给出；取不到时退回 %USERPROFILE%\Desktop
function Get-DesktopDir {
    $d = ''
    try { $d = [Environment]::GetFolderPath('Desktop') } catch { }
    if (-not $d) { $d = Join-Path $env:USERPROFILE 'Desktop' }
    if (-not (Test-Path $d)) { $d = Join-Path $env:USERPROFILE 'Desktop' }
    return $d
}

function Say($msg)  { Write-Host $msg }
function Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Bad($msg)  { Write-Host "  [X]  $msg" -ForegroundColor Red }

function Write-Utf8NoBom($path, $text) {
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-Utf8Bom($path, $text) {
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($true)))
}

function Read-Text($path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# 先备份再覆盖，备份名带时间戳
function Backup-File($path) {
    if (Test-Path $path) {
        $bak = "$path.bak-$Stamp"
        Copy-Item $path $bak -Force
        return $bak
    }
    return $null
}

function Test-IsPurgeHook($h) {
    foreach ($item in @($h)) {
        if ($null -eq $item) { continue }
        if ($item.command -and ($item.command -like '*purge-turn.ps1*')) { return $true }
        if ($item.hooks) {
            foreach ($sub in @($item.hooks)) {
                if ($sub.command -and ($sub.command -like '*purge-turn.ps1*')) { return $true }
            }
        }
    }
    return $false
}

function Save-Settings($cfg) {
    $json = $cfg | ConvertTo-Json -Depth 20
    if (Test-Path $SettingsPath) {
        if ((Read-Text $SettingsPath) -eq $json) { return $false }
        Backup-File $SettingsPath | Out-Null
    }
    Write-Utf8NoBom $SettingsPath $json
    return $true
}

# ---------------------------------------------------------------- 找 claude
function Find-Claude {
    $cands = @(
        (Join-Path $env:APPDATA 'npm\claude.cmd'),
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\claude.cmd'),
        (Join-Path $env:LOCALAPPDATA 'Programs\claude\claude.exe'),
        (Join-Path $env:USERPROFILE 'AppData\Roaming\npm\claude.ps1')
    )
    foreach ($c in $cands) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source -like '*.ps1') {
            $sibling = [System.IO.Path]::ChangeExtension($cmd.Source, '.cmd')
            if (Test-Path $sibling) { return $sibling }
        }
        return $cmd.Source
    }
    return $null
}

# ================================================================ 卸载
if ($Uninstall) {
    Say ''
    Say '========== 卸载提示词覆盖 =========='
    Say ''

    if (Test-Path $SettingsPath) {
        try {
            $cfg = Read-Text $SettingsPath | ConvertFrom-Json
            $removed = $false
            if ($cfg.PSObject.Properties['hooks'] -and $cfg.hooks.PSObject.Properties['UserPromptSubmit']) {
                $kept = @()
                foreach ($item in @($cfg.hooks.UserPromptSubmit)) {
                    if ($null -eq $item) { continue }
                    if (Test-IsPurgeHook $item) { $removed = $true } else { $kept += $item }
                }
                if ($removed) {
                    if ($kept.Count -eq 0) {
                        $cfg.hooks.PSObject.Properties.Remove('UserPromptSubmit')
                    } else {
                        $cfg.hooks | Add-Member -NotePropertyName UserPromptSubmit -NotePropertyValue @($kept) -Force
                    }
                    if ($cfg.PSObject.Properties['skipDangerousModePermissionPrompt'] -and $cfg.skipDangerousModePermissionPrompt -eq $true) {
                        $cfg.PSObject.Properties.Remove('skipDangerousModePermissionPrompt')
                    }
                    Save-Settings $cfg | Out-Null
                    Ok '已从 settings.json 移除 hook'
                } else {
                    Warn 'settings.json 里没找到本工具的 hook，跳过'
                }
            } else {
                Warn 'settings.json 里没有 hook 配置，跳过'
            }
        } catch {
            Bad "读取 settings.json 失败，没改动它：$($_.Exception.Message)"
        }
    }

    foreach ($p in @($PromptPath, $HookPath, $ContextPath)) {
        if (Test-Path $p) {
            $bak = Backup-File $p
            Remove-Item $p -Force
            Ok "已删除 $p（备份 $bak）"
        }
    }

    $desktop = Get-DesktopDir
    foreach ($name in @('Claude Code (Override).bat', 'Claude Code (Purge).bat')) {
        $bat = Join-Path $desktop $name
        if (Test-Path $bat) { Remove-Item $bat -Force; Ok "已删除桌面启动器 $name" }
    }

    Say ''
    Say '卸载完成。原版 Claude Code 不受影响，直接用 claude 命令即可。'
    Say ''
    exit 0
}

# ================================================================ 安装
Say ''
Say '=================================================='
Say '   Claude Code 提示词覆盖 · 一键安装'
Say '=================================================='
Say ''

if (-not (Test-Path $FilesDir)) {
    Bad "安装包不完整：找不到 files 目录（$FilesDir）"
    Say '请重新解压完整的压缩包再运行。'
    Say ''
    Read-Host '按回车退出'
    exit 1
}

# --- 1. 环境
Say '[1/5] 检查环境'
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    Ok "已创建 $ClaudeDir"
} else {
    Ok "已有 $ClaudeDir"
}
if (-not (Test-Path $HooksDir)) { New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null }

$claude = Find-Claude
$claudeReady = $true
if ($claude) {
    Ok "找到 Claude Code：$claude"
} else {
    $claudeReady = $false
    Warn '没找到 claude 命令。'
    Say '    请先安装 Claude Code（任一方式）：'
    Say '      npm install -g @anthropic-ai/claude-code'
    Say '    装好后重新双击本安装包即可。'
    Say '    现在先继续装配置文件，稍后自己改桌面启动器里的路径也行。'
    $claude = 'claude'
}

# --- 2. system prompt
Say ''
Say '[2/5] 部署 system prompt'
if (-not (Test-Path (Join-Path $FilesDir 'system-prompt.md'))) {
    Bad '缺少 files\system-prompt.md，安装包不完整'
    Read-Host '按回车退出'
    exit 1
}
$newPrompt = Read-Text (Join-Path $FilesDir 'system-prompt.md')
if (Test-Path $PromptPath) {
    $oldPrompt = Read-Text $PromptPath
    if ($oldPrompt -eq $newPrompt) {
        Ok 'system-prompt.md 内容相同，跳过'
    } else {
        $bak = Backup-File $PromptPath
        Write-Utf8NoBom $PromptPath $newPrompt
        Ok "已更新 system-prompt.md（旧的备份为 $(Split-Path -Leaf $bak)）"
    }
} else {
    Write-Utf8NoBom $PromptPath $newPrompt
    Ok "已写入 $PromptPath"
}

# --- 3. hook 文件
Say ''
Say '[3/5] 部署 hook 文件'
foreach ($pair in @(
    @{src = 'purge-turn.ps1';         dst = $HookPath;    bom = $true },
    @{src = 'purge-turn-context.md';  dst = $ContextPath; bom = $false }
)) {
    $srcPath = Join-Path $FilesDir $pair.src
    if (-not (Test-Path $srcPath)) { Bad "缺少 $($pair.src)"; continue }
    $txt = Read-Text $srcPath
    if ($pair.bom) { Write-Utf8Bom $pair.dst $txt } else { Write-Utf8NoBom $pair.dst $txt }
    Ok "已写入 $($pair.dst)"
}

# --- 4. 合并 settings.json
Say ''
Say '[4/5] 配置 settings.json'
$cfg = $null
if (Test-Path $SettingsPath) {
    try {
        $raw = Read-Text $SettingsPath
        if ($raw.Trim()) { $cfg = $raw | ConvertFrom-Json }
    } catch {
        Bad "settings.json 不是合法 JSON，没有改动它。"
        Say "    请先手动修好 $SettingsPath，或删掉它重装。"
        $cfg = $null
    }
}
if ($null -eq $cfg) {
    if (Test-Path $SettingsPath) {
        $cfg = $null
    } else {
        $cfg = [PSCustomObject]@{}
        Ok 'settings.json 不存在，新建一份'
    }
}

if ($null -ne $cfg) {
    # hooks.UserPromptSubmit
    if (-not $cfg.PSObject.Properties['hooks']) {
        $cfg | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{})
    }
    if (-not $cfg.hooks.PSObject.Properties['UserPromptSubmit']) {
        $cfg.hooks | Add-Member -NotePropertyName UserPromptSubmit -NotePropertyValue @()
    }
    $existing = @($cfg.hooks.UserPromptSubmit) | Where-Object { $null -ne $_ }
    if (Test-IsPurgeHook $existing) {
        Ok 'hook 已存在，不重复添加'
    } else {
        $hookCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$HookPath`""
        $entry = [PSCustomObject]@{
            matcher = ''
            hooks   = @([PSCustomObject]@{ type = 'command'; command = $hookCmd })
        }
        $cfg.hooks | Add-Member -NotePropertyName UserPromptSubmit -NotePropertyValue (@($existing) + $entry) -Force
        Ok '已添加 UserPromptSubmit hook'
    }

    # bypassPermissions 不再每次确认
    if (-not $cfg.PSObject.Properties['skipDangerousModePermissionPrompt']) {
        $cfg | Add-Member -NotePropertyName skipDangerousModePermissionPrompt -NotePropertyValue $true
        Ok '已开启 skipDangerousModePermissionPrompt（否则每次启动都弹确认）'
    }

    # 非官方后端才设 128K 上下文，官方 API 保持 200K
    $isThirdParty = $false
    if ($cfg.PSObject.Properties['env'] -and $cfg.env.PSObject.Properties['ANTHROPIC_BASE_URL']) {
        $u = [string]$cfg.env.ANTHROPIC_BASE_URL
        if ($u -and $u -notlike '*api.anthropic.com*') { $isThirdParty = $true }
    }
    if ($isThirdParty) {
        if (-not $cfg.env.PSObject.Properties['CLAUDE_CODE_MAX_CONTEXT_TOKENS']) {
            $cfg.env | Add-Member -NotePropertyName CLAUDE_CODE_MAX_CONTEXT_TOKENS -NotePropertyValue '131072'
            Ok '检测到第三方后端，已设 CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072'
        } else {
            Ok "已有 CLAUDE_CODE_MAX_CONTEXT_TOKENS=$($cfg.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS)，保持不动"
        }
    }

    if (Save-Settings $cfg) { Ok 'settings.json 已保存' } else { Ok 'settings.json 无变化，没动它' }
}

# --- 5. 桌面启动器
Say ''
Say '[5/5] 创建桌面启动器'
$desktop = Get-DesktopDir
if (-not (Test-Path $desktop)) { New-Item -ItemType Directory -Path $desktop -Force | Out-Null }
$batPath = Join-Path $desktop 'Claude Code (Override).bat'
$bat = @"
@echo off
chcp 65001 >nul
title Claude Code (Override)
cd /d "%USERPROFILE%"
"$claude" --permission-mode bypassPermissions --system-prompt-file "%USERPROFILE%\.claude\system-prompt.md"
echo.
echo Claude Code has closed.
pause
"@
Write-Utf8NoBom $batPath $bat
Ok "已创建 $batPath"

if (-not $claudeReady) {
    Warn '还没找到 claude 命令，这个启动器现在打不开。装完 Claude Code 后重跑一次安装包即可。'
}

Say ''
Say '=================================================='
Say '  安装完成'
Say '=================================================='
Say ''
Say '以后启动：双击桌面的 "Claude Code (Override).bat"'
Say '  不要用旧的快捷方式或 --continue，每次都要开新会话。'
Say ''
Say '想改提示词内容：编辑 %USERPROFILE%\.claude\system-prompt.md'
Say '想卸掉：双击本包的 卸载.bat'
Say ''
Read-Host '按回车关闭'
