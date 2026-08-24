# CodeBuddy 集成

## 概述

Liang 通过 CodeBuddy Code 的 Hooks 机制接入。CodeBuddy 官方声明「完全兼容 Claude Code Hooks 规范」（环境变量 `CLAUDE_PROJECT_DIR` 兼容、stdin/stdout JSON 结构一致、事件命名一致），因此接入方式与 Claude Code 几乎完全一致，直接照抄 Claude Code 的接入模式。

## 配置

- 配置文件：`~/.codebuddy/settings.json`（用户级）；项目级为 `<workspace>/.codebuddy/settings.json`
- 配置结构：三层嵌套 `hooks` → 事件名 → `[{ matcher, hooks: [{ type, command }] }]`
- 桥接脚本：`~/.codebuddy/hooks/codebuddy-bridge.sh`
- 事件文件：`~/.liang/codebuddy-events.jsonl`

## 安装检测

CodeBuddy Code 是 CLI 工具，二进制名为 `codebuddy`，三种官方安装方式：

| 安装方式 | 二进制路径 |
| --- | --- |
| npm / pnpm / yarn / bun 全局 | `~/.nvm/versions/node/*/bin/codebuddy`、`~/.npm-global/bin/codebuddy` |
| Homebrew | `/opt/homebrew/bin/codebuddy`、`/usr/local/bin/codebuddy` |
| 官方 install.sh 原生二进制 | `~/.local/bin/codebuddy`、`~/.codebuddy/bin/codebuddy` |

关键：CodeBuddy 的 IDE 集成（VS Code / JetBrains / Zed）本质都是 CLI 作为后端（插件启动 `codebuddy` 进程 + MCP 连接），**没有独立的桌面版 app**。因此检测 `codebuddy` CLI 二进制即覆盖全部场景，无需像 Codex 那样额外检测桌面版。

## 事件映射

| CodeBuddy 事件 | Liang hook | 状态 |
| --- | --- | --- |
| `SessionStart` | `sessionStart` | processing |
| `SessionEnd` | `sessionEnd` | idle |
| `UserPromptSubmit` | `beforeSubmitPrompt` | processing |
| `PreToolUse` | `preToolUse` | processing |
| `PostToolUse` | `postToolUse` | processing |
| `Stop` | `stop` | completed（恒） |
| `SubagentStop` | `subagentStop` | completed（恒） |

`Notification`、`PreCompact` 等事件被 bridge 脚本忽略（不进入状态机）。

## 限制

1. **无法区分成功/失败**：CodeBuddy 的 `Stop` 无 `status` 字段（Claude Code 有 `completed`/`error`/`aborted`），`SubagentStop` 无 `is_error`，且没有 `PostToolUseFailure` 事件。因此任务结束恒映射为 `completed`（success），与 Codex 的「恒 success」限制相同。
2. **无 `SubagentStart` 事件**：子代理启动不产生事件，无法检测子代理的开始。
3. **`/hooks` 审核面板**：直接编辑 `settings.json` 不会立即生效，CodeBuddy 在启动时捕获 hooks 快照，外部修改需在 CodeBuddy 内 `/hooks` 菜单审核才应用。

## 支持的客户端

- CodeBuddy Code CLI
- IDE 插件（VS Code / JetBrains / Zed），本质都是 CLI 作为后端 + MCP 连接

云端会话不支持（与 Cursor / Claude Code / Codex 一致）。

## 与 Codex 的差异

CodeBuddy 与 Codex 的接入方式几乎相同（都无状态字段、恒 completed），主要差异：

- Codex 检测「CLI + ChatGPT.app 桌面版」两个来源；CodeBuddy 只需检测 CLI 一个来源（IDE 集成依赖 CLI）。
- Codex 配置文件是 `~/.codex/hooks.json`（两层嵌套），CodeBuddy 是 `~/.codebuddy/settings.json`（三层嵌套，与 Claude Code 相同）。
