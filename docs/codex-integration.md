# Codex 集成调研

> 日期：2026-08-20（调研）/ 2026-08-23（开发完成）
> 状态：已开发

## 一、结论

Codex（OpenAI Codex CLI，Rust 实现）**有完整的 hooks 机制**，且与 Claude Code 的 hooks 结构**几乎一模一样**。复用度比之前 Cursor → Claude Code 还要高。

**重要：ChatGPT.app 桌面应用 = Codex 桌面版**。Codex App 已并入 ChatGPT 桌面端（内置 Codex 引擎，共用 `~/.codex` 配置），同样支持 hooks（读 `~/.codex/hooks.json` 或 `config.toml` 内联 `[hooks]`）。因此接入检测需同时覆盖 `codex` CLI 与 `/Applications/ChatGPT.app`。

**支持的客户端**：Codex CLI（Terminal）+ ChatGPT 桌面版（Codex 模式）。云端会话不读本地 hooks 配置。

| 维度 | Claude Code | Codex |
|---|---|---|
| 配置文件 | `~/.claude/settings.json` | `~/.codex/hooks.json`（JSON）或 `~/.codex/config.toml`（TOML 内联） |
| 配置结构 | 三层（事件 → matcher 组 → `{type, command}` handlers） | **三层（相同）** |
| 事件名 | CamelCase | **CamelCase（相同）** |
| stdin 字段 | `session_id`/`prompt_id`/`cwd`/`hook_event_name`/`permission_mode` | `session_id`/`turn_id`/`cwd`/`hook_event_name`/`permission_mode`/`model` |
| 成功/失败区分 | `Stop` vs `StopFailure` + `SubagentStop.is_error` | **无（限制 1）** |

## 二、Hook 事件

Codex 事件（CamelCase）：`SessionStart`、`SessionEnd`、`SubagentStart`、`SubagentStop`、`PreToolUse`、`PostToolUse`、`UserPromptSubmit`、`Stop`、`PreCompact`、`PostCompact`、`PermissionRequest`。

与 Claude Code 对比：
- **Codex 独有**：`PermissionRequest`（权限审批，本项目无关可忽略）
- **Codex 缺失**：`PostToolUseFailure`、`StopFailure`、`Notification`

## 三、配置结构（hooks.json）

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          { "type": "command", "command": "/path/to/codex-bridge.sh" }
        ]
      }
    ]
  }
}
```

三层结构：事件名 → matcher 组（正则，`"*"` 匹配全部）→ handlers（`type` + `command`）。与 Claude Code 的 `settings.json` hooks 字段完全一致。

## 四、可复用清单

| 组件 | 复用程度 |
|---|---|
| `FileHookAdapter`（通用文件监听） | ✅ 零改动，加 `codex-events.jsonl` 实例 |
| `StateEngine` 状态机 | ✅ 零改动 |
| `HookEvent` 模型 | ✅ 复用，字段映射略调（`turn_id → generation_id`） |
| `ClaudeCodeSetupManager` 合并写入逻辑 | 🔧 高度复用（结构一样，只改目标文件 + 事件名） |
| `ClaudeSetupSection` / `ClaudeCodePage` UI | 🔧 照抄改文案 |
| 桥接脚本骨架（stdin→归一化→JSONL→静默 exit 0） | 🔧 复用 |
| `IDE` 枚举（已预留 `codex`）+ `iconImage` 图标系统 | ✅ 加 case + 图标资源 |

## 五、关键限制

### 限制 1（最重要）：无法区分成功/失败
Codex 的 `Stop` / `SubagentStop` **没有 `status`、`is_error` 字段**，也**没有 `StopFailure` 事件**（Cursor 有 `status`，Claude Code 有 `StopFailure` + `is_error`）。因此 `Stop` / `SubagentStop` 只能映射 `success`，**Codex 任务结束恒为绿色，无法提示 error**。

> **关于 `decision` / `reason` 的澄清**（易混淆点）：这两个字段是 **hook 脚本「输出」给 Codex** 的（hook → Codex），用于控制流——`decision: "block"` 表示「要求 Codex 继续工作（不要停止）」，`reason` 是继续时的新 prompt 文本。它们**不是** Codex 传给 hook 的输入，与「任务成功/失败状态」完全无关，不能用来判断 error。

### 限制 2：hook 需要用户「信任」才会执行
Codex 非托管 hook 首次必须经 `/hooks` 命令审查信任，否则**被跳过不执行**；hook 脚本内容一旦修改，会重新标记待审查、再次跳过直到重新信任。这是 Cursor / Claude Code 都没有的额外步骤——自动安装后用户仍需手动进 Codex 敲 `/hooks` 信任，否则收不到事件。

### 限制 3：无 `prompt_id`，用 `turn_id` 替代
Codex 没有 `prompt_id`（每次 prompt 一个 UUID），只有 `turn_id`（回合 ID）。去重时用 `turn_id` 替代 `generation_id`，粒度略粗但够用。

### 限制 4：`SessionEnd` 触发延迟
Codex 的 `SessionEnd` 在「会话空闲 30 分钟」后才触发（非关闭即触发），且该 hook 默认 timeout 仅 1 秒。`idle` 状态切换会比 Cursor / Claude Code 慢，需依赖现有「5 分钟无事件心跳超时」兜底。

## 六、事件 → LiangState 映射

| Codex 事件 | 归一化 → LiangState |
|---|---|
| `SessionStart`/`UserPromptSubmit`/`PreToolUse`/`PostToolUse`/`SubagentStart` | `processing` |
| `Stop` / `SubagentStop` | `success`（**无法区分 error**） |
| `SessionEnd` | `idle` |

## 七、字段映射（Codex → 统一 HookEvent）

| Codex 字段 | 统一字段 | 备注 |
|---|---|---|
| `hook_event_name` | `hook`（归一化小驼峰） | |
| `session_id` | `conversationID` | |
| `turn_id` | `generationID` | 替代 prompt_id（限制 3） |
| `tool_use_id` | `taskID`/`toolUseID` | |
| `tool_name` | `toolName` | |
| `agent_id` | `subagentID` | |
| — | `status` | Codex 无此字段，恒 success |

### Stop / SubagentStop 输入字段（完整清单）

**公共字段**：`session_id`、`transcript_path`、`cwd`、`hook_event_name`、`model`、`permission_mode`

**Stop 事件专属**：`turn_id`、`stop_hook_active`、`last_assistant_message`

**SubagentStop 事件专属**：`turn_id`、`agent_id`、`agent_type`、`agent_transcript_path`、`stop_hook_active`、`last_assistant_message`

> 输入字段中**没有** `status` / `error` / `success`，确认无法判断成功/失败。

### hook 输出字段（hook → Codex，与本项目无关但易混淆）

- `continue`（boolean，false=停止）、`stopReason`、`systemMessage`、`suppressOutput`
- `decision`（`"block"` = 要求继续）、`reason`（继续的 prompt 文本）
- 退出码 `0`=正常；`2`=等效 `decision:"block"`；其他非零=hook 失败

> 本项目的桥接脚本是「纯副作用」hook：stdin 读元数据写本地文件后 **exit 0 且 stdout 不输出任何内容**，因此不会触发 `decision`/`continue` 等控制流语义，Codex 行为不受影响。

## 八、待确认决策

1. **限制 1（无法区分 error）**：是否接受 Codex 任务结束恒 success（绿色）？
2. **限制 2（信任机制）**：自动安装后仍需用户 `/hooks` 信任，是否在设置页加提示文案？
