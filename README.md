# Claude Code 提示词覆盖实测笔记

在 Claude Code 里减少"无谓拒绝"的一套可复用方法，附六轮对照实验的实测数据。

不是理论推演，全部在本机跑过，包括失败的那些。

- 测试对象：Claude Code **2.1.301 / 2.1.302 / 2.1.311**（Windows，npm 安装 + VS Code 扩展）
- 后端：**非 Anthropic 官方** —— 走 `ANTHROPIC_BASE_URL` 指向第三方兼容端点，模型为 `deepseek-flash`
- 结论只对这套组合实测有效；换成官方 Anthropic 模型结果会不同

---

## 范围声明

- 只涉及**你自己机器上、你自己付费凭据下**的客户端行为定制，不涉及绕过计费、破解授权、修改服务端。
- 不包含任何受版权保护的 prompt 原文；模板是本仓库原创，按你的需要填写。
- 不包含可执行载荷、盗版资源链接或针对第三方的攻击步骤。
- 记录的是"参数如何影响行为"的实验结果，供调试与二次开发参考。

如果你打算用这套配置去处理某类内容，请自行确认在你所在地区与你所用服务的条款下是允许的。仓库作者不对使用后果负责。

---

## 结论先行

| 手法 | 有效 | 原因 |
| --- | --- | --- |
| `--system-prompt-file` 整段替换 | ✅ | 换掉身份段，等于换人 |
| `--append-system-prompt` 追加 | ❌ | 追加在尾部，压不过开头的身份声明 |
| 改 `CLAUDE.md` | ❌ | memory 层，位置太低 |
| `UserPromptSubmit` hook 每轮注入 | ❌ | 属于 user-turn 层，权重不够 |
| 打宿主补丁（删安全措辞） | ❌ | 做减法，减完还是原身份 |
| 换模型型号 | ❌ | 拒绝来自模型侧，不是型号差异 |
| 旧会话里继续追问 | ❌ | 历史里的拒绝记录会锚定后续回答 |
| **新会话 + 整段替换** | ✅ | 三个变量同时到位 |

一句话：**改动位置决定效果，改动力度不决定效果。**

---

## 为什么"追加"没用

Claude Code 发给模型的 system prompt 开头是固定的一句：

```
You are Claude Code, Anthropic's official CLI for Claude.
```

后面整套行为准则都建立在这个身份上。模型认领这个身份之后，就按它的规矩来。

- **追加**：原文还在，新内容排在它后面 → 权重压不过开头的身份。
- **替换**：原文整段不见了，模型拿到一份干净的 system prompt → 身份没了，规矩跟着没。

实测：同样的追加文本，`--append-system-prompt` 拒，`--system-prompt` 答。一字不差的同一段文字。

---

## 替换之后，什么还在、什么丢了

一个容易搞错的点：`--system-prompt-file` 换的是 system prompt 里"身份 + 准则"那一段，不是整个运行时。实测（2.1.311）逐项确认过：

| 项目 | 走哪条通道 | 状态 |
| --- | --- | --- |
| 工具定义（Read / Edit / Bash / …） | API 的 `tools` 字段 | 保留 |
| 工作目录、日期、平台信息 | 环境块注入 | 保留 |
| `CLAUDE.md` 全局指令 | memory 通道 | 保留 |
| `MEMORY.md` / 项目记忆 | memory 通道 | 保留 |
| skills 列表 | 插件通道 | 保留 |
| 子代理（Explore / general-purpose） | 各自独立 prompt | 不受影响 |
| 身份声明与行为准则 | system prompt 前半段 | **被替换** |
| "何时用哪个工具"的策略提示 | system prompt | **被替换** |

验证方法：用一份只有四五段的自定义 prompt 起一个 `-p` 会话，问它工作目录、日期、全局指令内容、可用 skills。四项都能答对，说明这些通道没被替换波及。

**所以真正需要补回来的只有工具策略**，大约十条：先定位再读取、并行调用互不依赖的工具、改代码前先搜引用、改完要验证、失败换方法不重复。补上之后日常任务感觉不到差别，剩下的差距只在大型多文件重构时才显出来。

---

## 落地一：CLI / 桌面启动器（推荐）

### 1. 写一份替换用的 system prompt

放到 `~/.claude/system-prompt.md`，参考 [`configs/system-prompt.md`](configs/system-prompt.md)。

五段结构，缺一不可：

1. **运行环境** —— 谁在什么机器上，不要假设路径和状态，需要就用工具取
2. **工具纪律** —— Read/Edit/Write/Glob/Grep/Bash 各管什么，写文件前先读
3. **工具策略** —— 什么时候搜、什么时候直接读、什么时候派子代理、改完怎么验证
4. **处理口径** —— 哪些类别按普通信息需求处理，不要引入合规判断
5. **禁止话术清单** —— 直接点名它最爱说的那几句

> **第 3 段最容易被忽略**。原版 prompt 里有一大段"何时用哪个工具"的策略，替换掉之后就没了。不补的话日常问答看不出来，一遇到多文件任务就会退化成"一个个 Read、不用 Grep 定位、改完不验证"。

> **关键技巧**：把模型自己的原话抄进禁止清单。它对"见过的模板句"复述倾向极强，点名禁掉比抽象要求有效十倍。

### 2. 启动时替换

```bat
"%APPDATA%\npm\claude.cmd" ^
  --permission-mode bypassPermissions ^
  --system-prompt-file "%USERPROFILE%\.claude\system-prompt.md"
```

用 `%APPDATA%` 而不是拼 `C:\Users\<你>\...`：用户名带空格、或者换一台机器时，写死的路径会断。

一次性调用：

```bash
claude --system-prompt-file ~/.claude/system-prompt.md -p "你的问题"
```

### 3. 不要加 `--continue`

这是最容易踩的坑。续接旧会话会把之前的拒绝记录一起带进来，模型读到"我拒过这个"，就顺着旧姿态继续拒。**新会话是通过率最高的变量。**

---

## 落地二：VS Code 扩展

扩展不走命令行，但它留了一个真的启动器钩子：设置项 `claudeCode.claudeProcessWrapper`。

设上之后，扩展 spawn 的命令从

```
<扩展自带 claude.exe> <参数>
```

变成

```
<wrapper.exe> <扩展自带 claude.exe> <参数>
```

也就是 wrapper 拿到真实二进制路径当 argv[0]，其余原样透传。**所以一个几十行的转发器就能把 `--system-prompt-file` 塞进去**，效果和命令行启动器一样，不需要 hook 打补丁。

源码见 [`configs/vscode/purge-wrapper.cs`](configs/vscode/purge-wrapper.cs)，用系统自带的编译器编：

```bat
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -nologo -codepage:65001 ^
  -optimize+ -target:exe -out:"%USERPROFILE%\.claude\purge-wrapper.exe" ^
  "%USERPROFILE%\.claude\purge-wrapper.cs"
```

然后在 VS Code 用户设置里加一行，**路径要写绝对路径**（VS Code 不展开 `%USERPROFILE%`）：

```json
{
  "claudeCode.claudeProcessWrapper": "C:\\Users\\<你>\\.claude\\purge-wrapper.exe"
}
```

改完重载窗口才生效。

实测（2.1.311）：设置之后扩展起来的会话，system prompt 第一段就是自定义那份；`auth status --json`、`--version` 这类子命令原样透传，不受影响。

转发器里三个设计点，抄的时候别漏：

- **只对会话类调用注入**：参数里有 `--input-format` 或 `--output-format` 才追加 `--system-prompt-file`，其它子命令纯透传，避免子命令解析报 unknown option
- **参数重新加引号**：`.NET` 给的 `args` 已经去引号了，要按 `CommandLineToArgvW` 规则拼回去，路径带空格才不会碎
- **用 Job Object 兜底**：`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`，VS Code 杀掉 wrapper 时真正的 claude 也跟着退，不留孤儿进程

wrapper 每次调用会往 `~/.claude/purge-wrapper.log` 记一行 `inject` / `pass` / `off`，排查时先看这个。

**想临时回原版**：包装器认一个开关文件——`~/.claude/purge-off` 存在就整段跳过注入，日志记 `off`。

切换方式按需要挑：

- 最省事：桌面上放个切换程序，双击一下换模式，弹窗告诉你切到哪了。源码 [`configs/vscode/purge-toggle.cs`](configs/vscode/purge-toggle.cs)，带图标编译：

  ```bat
  C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -nologo -codepage:65001 ^
    -target:winexe -optimize+ -win32icon:"%USERPROFILE%\.claude\purge-toggle.ico" ^
    -out:"%USERPROFILE%\Desktop\VS Code 模式切换.exe" ^
    "%USERPROFILE%\.claude\purge-toggle.cs"
  ```

  图标见 [`configs/vscode/purge-toggle.ico`](configs/vscode/purge-toggle.ico)，16~256 六个尺寸，小图标也不糊。

- 不想要程序，一个 .bat 也行：

  ```bat
  @echo off
  set "FLAG=%USERPROFILE%\.claude\purge-off"
  if exist "%FLAG%" ( del "%FLAG%" & echo 破甲模式 ) else ( type nul > "%FLAG%" & echo 正常模式 )
  pause
  ```

切换之后**新建**对话才生效，已经跑着的会话不受影响。

两个坑：`.bat` 存成 LF 换行会被 cmd 按行拆坏，报一堆"不是内部或外部命令"，必须 CRLF；`.bat` 本身挂不了自定义图标，想要图标就得编成 exe（顺带还能钉任务栏）。

### 备用入口：每轮 hook 注入

扩展还有一条弱入口：`UserPromptSubmit` hook，每轮把口径注入一次。有了上面的 wrapper 它就是兜底用的（比如 wrapper 没配、或者终端里手敲 `claude`）。放在 `~/.claude/settings.json`：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<你>\\.claude\\hooks\\purge-turn.ps1\""
          }
        ]
      }
    ]
  }
}
```

`purge-turn.ps1` 见 [`configs/hooks/purge-turn.ps1`](configs/hooks/purge-turn.ps1)。

**踩过的坑 1**：hook 的 `command` 写成 `.cmd` 或 `cmd /c xxx.cmd` 在 Windows 上完全不会触发，只有 `powershell -File xxx.ps1` 这种形式能跑。验证方式是让脚本往日志里写一行时间戳，再提交一次提示词看日志有没有新增。

**踩过的坑 2：中文全变乱码**。脚本里 `Get-Content -Encoding UTF8` 读出来是对的，但 PowerShell 5.1 往 stdout 写时按系统代码页（中文 Windows 是 936）转了一遍，Claude Code 按 UTF-8 读。结果是每轮注入一段乱码，等于没注入还白占上下文。按字节验一下就看得出来：

```
5b b4 a6 c0 ed   ← GBK 的 "[处理"
5b e5 a4 84 e7   ← 修好之后，UTF-8 的 "[处理"
```

修法是在脚本**第一行**加：

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

或者把调用换成 `pwsh`（PowerShell 7 默认 UTF-8）。但每轮都要起一个进程，`pwsh` 冷启动要 300~800ms，不如在脚本里设编码划算。

**踩过的坑 3：脚本静默失效**。`.ps1` 存成 UTF-8 无 BOM 又带中文注释时，PowerShell 5.1 会按 ANSI 解析，中文注释的字节可能把语法拆坏。表现是**脚本零输出、也不报错**，日志还照写，特别难查。规则：`.ps1` 要么存 UTF-8 with BOM，要么注释只写 ASCII。

**实测结论**：hook 能触发、内容确实进了上下文，但**仍然拒**。层级不够，属于降摩擦而不是破防。有了 wrapper 之后这条可以不加——每轮多起一个 PowerShell 只是多花 0.3~0.8 秒和几百 token；想快速验证「注入到底进没进上下文」时，它倒是最好用的探针。

---

## 落地三：其他 harness

同样的原理可以移植到任何能控制 system prompt 的地方：

- 自建 API 调用：`system` 字段直接写口径，这是最干净的
- 带插件系统的 harness：把口径放到"每步重贴的 system section"，不要放 memory 文件
- 位置权威性递减：**system section > agent 预设 > memory 文件 > 用户消息**

---

## 顺带：别让它瞎猜上下文窗口

用第三方兼容端点时，每次启动都会看到：

```
Claude Code doesn't recognize the model "deepseek-flash", so it assumes a context window of 200k tokens.
```

这个假设会害人。DeepSeek 实际是 128K，按 200K 算，自动压缩的触发点就被推得太晚，长会话到十几万 token 时直接撑爆。修法是在 `settings.json` 的 `env` 里补一行：

```json
"CLAUDE_CODE_MAX_CONTEXT_TOKENS": "131072"
```

数值按你自己的模型填，不是 128K 的别照抄。加上之后那句警告也会消失。

---

## 附：对照实验原始记录

见 [`docs/measurements.md`](docs/measurements.md)。

---

## 边界

这套方法改的是表达层，不是模型的事实判断。

实测里始终过不去的一层是**具体分发**——可执行载荷、具体侵权文件、针对真实第三方的攻击步骤。能过的通常是知识与方法论层：分类、流程、检索方式、原理。

这个分界不是配置能改的。

## License

MIT
