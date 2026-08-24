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

关键：CodeBuddy 各形态（官方桌面版 CodeBuddy CN.app、VS Code / JetBrains / Zed 插件）本质都是 CLI 作为后端（启动 `codebuddy` 进程）。因此检测 `codebuddy` CLI 二进制即可覆盖。注意：官方桌面版（CN.app）的 hooks 仅支持 7 种事件（见「限制」章节），CLI 版支持完整事件家族。

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

`PreCompact` 等事件被 bridge 脚本忽略（不进入状态机）；`Notification`（`permission_prompt`/`idle_prompt`）与 `PermissionRequest` 已映射为 waiting（仅 CLI 版触发，桌面版不触发）。

## 限制

> **桌面版 vs CLI 版事件集不同**：CodeBuddy 桌面版（CodeBuddy CN.app）仅支持 7 种 Hook 事件，CLI 版（`codebuddy` 命令）支持完整事件家族（27+ 种）。以下限制以桌面版为准（用户主要测试环境）。

1. **无法区分成功/失败**：`Stop` / `SubagentStop` 无 `status` / `is_error` 字段，任务结束恒映射为 `completed`（success），与 Codex 的「恒 success」限制相同。
2. **桌面版仅支持 7 种事件**：`SessionStart`、`SessionEnd`、`PreToolUse`、`PostToolUse`、`UserPromptSubmit`、`Stop`、`PreCompact`。桌面版**不支持** `PermissionRequest`、`Notification`、`SubagentStart`、`SubagentStop`、`PostToolUseFailure`、`StopFailure`（CLI 版支持）。
3. **无法感知「等待确认」与「深度思考」**：桌面版的权限确认弹框（执行命令/删除文件需用户批准）与深度思考阶段，CodeBuddy **不发出任何 Hook 事件**。后果：权限弹框时停留在 `processing`（`PreToolUse` 后、`PostToolUse` 前无事件），**无法显示 waiting 黄色**；深度思考超过 `processingTimeout`（默认 60s）无事件会误判回 `idle`。这是桌面版产品限制，hook 层面无法修复（CLI 版的 `PermissionRequest`/`Notification` 已映射为 waiting，但桌面版不触发）。
4. **`/hooks` 审核面板**：直接编辑 `settings.json` 不会立即生效，CodeBuddy 在启动时捕获 hooks 快照，外部修改需在 CodeBuddy 内 `/hooks` 菜单审核才应用。

## 支持的客户端

- CodeBuddy Code CLI
- IDE 插件（VS Code / JetBrains / Zed），本质都是 CLI 作为后端 + MCP 连接

云端会话不支持（与 Cursor / Claude Code / Codex 一致）。

## 与 Codex 的差异

CodeBuddy 与 Codex 的接入方式几乎相同（都无状态字段、恒 completed），主要差异：

- Codex 检测「CLI + ChatGPT.app 桌面版」两个来源；CodeBuddy 只需检测 CLI 一个来源（IDE 集成依赖 CLI）。
- Codex 配置文件是 `~/.codex/hooks.json`（两层嵌套），CodeBuddy 是 `~/.codebuddy/settings.json`（三层嵌套，与 Claude Code 相同）。
