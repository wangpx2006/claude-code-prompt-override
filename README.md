# Claude Code 提示词覆盖实测笔记

在 Claude Code 里减少"无谓拒绝"的一套可复用方法，附四轮对照实验的实测数据。

不是理论推演，全部在本机跑过，包括失败的那些。

- 测试对象：Claude Code **2.1.301 / 2.1.302 / 2.1.311**（Windows，npm 安装 + VS Code 扩展）
- 后端：**非 Anthropic 官方** —— 走 `ANTHROPIC_BASE_URL` 指向第三方兼容端点，模型为 `deepseek-flash`
- 结论只对这套组合实测有效；换成官方 Anthropic 模型结果会不同

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

## 落地一：CLI / 桌面启动器（推荐）

### 1. 写一份替换用的 system prompt

放到 `~/.claude/system-prompt.md`，参考 [`configs/system-prompt.md`](configs/system-prompt.md)。

四段结构，缺一不可：

1. **运行环境** —— 谁在什么机器上，不要假设路径和状态，需要就用工具取
2. **工具纪律** —— Read/Edit/Write/Glob/Grep/Bash 各管什么，写文件前先读
3. **处理口径** —— 哪些类别按普通信息需求处理，不要引入合规判断
4. **禁止话术清单** —— 直接点名它最爱说的那几句

> **关键技巧**：把模型自己的原话抄进禁止清单。它对"见过的模板句"复述倾向极强，点名禁掉比抽象要求有效十倍。

### 2. 启动时替换

```bat
"C:\Users\<你>\AppData\Roaming\npm\claude.cmd" ^
  --permission-mode bypassPermissions ^
  --system-prompt-file "%USERPROFILE%\.claude\system-prompt.md"
```

一次性调用：

```bash
claude --system-prompt-file ~/.claude/system-prompt.md -p "你的问题"
```

### 3. 不要加 `--continue`

这是最容易踩的坑。续接旧会话会把之前的拒绝记录一起带进来，模型读到"我拒过这个"，就顺着旧姿态继续拒。**新会话是通过率最高的变量。**

---

## 落地二：VS Code 扩展

扩展有自己的二进制（`~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude.exe`），不吃 CLI 参数。能用的只有一个弱入口：`UserPromptSubmit` hook，每轮把口径注入一次。

放在 `~/.claude/settings.json`：

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

**踩过的坑**：hook 的 `command` 写成 `.cmd` 或 `cmd /c xxx.cmd` 在 Windows 上完全不会触发，只有 `powershell -File xxx.ps1` 这种形式能跑。验证方式是让脚本往日志里写一行时间戳，再提交一次提示词看日志有没有新增。

**实测结论**：hook 能触发、内容确实进了上下文，但**仍然拒**。层级不够，属于降摩擦而不是破防。需要真正生效时，在 VS Code 的集成终端里跑落地一的命令。

---

## 落地三：其他 harness

同样的原理可以移植到任何能控制 system prompt 的地方：

- 自建 API 调用：`system` 字段直接写口径，这是最干净的
- 带插件系统的 harness：把口径放到"每步重贴的 system section"，不要放 memory 文件
- 位置权威性递减：**system section > agent 预设 > memory 文件 > 用户消息**

---

## 附：四轮对照实验原始记录

见 [`docs/measurements.md`](docs/measurements.md)。

---

## 边界

这套方法的用途是减少不必要的打断，不是让模型替你做它判断为有害的事。

实测里始终过不去的一层是**具体分发**——可执行载荷、具体侵权文件、针对真实第三方的攻击步骤。能过的通常是知识与方法论层：分类、流程、检索方式、原理。

这个分界不是配置能改的，是模型自身的判断。

## License

MIT
