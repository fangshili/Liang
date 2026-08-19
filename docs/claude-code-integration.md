# Claude Code 接入调研

> 日期：2026-08-18
> 状态：调研完成，**尚未开发**
> 目标：在已接入 Cursor 的基础上，接入 Claude Code，复用现有事件管道与状态机。

## 一、总体结论

可复用约 70% 现有架构。Claude Code 的 hooks 协议与 Cursor 有 5 处本质差异，不能"复制粘贴"，需要新建独立的 adapter 与桥接脚本。

| 层级 | 复用程度 | 说明 |
|---|---|---|
| `StateEngine` 状态机 | ✅ 零改动 | 事件源无关，只消费统一 `HookEvent` |
| `HookEvent` 模型 | 🔧 增解析入口 | 加 `init?(claudePayload:)` |
| `LiangState` 枚举 | ✅ 零改动 | 枚举不变，只在映射处加分支 |
| `TaskItem` / 任务列表 / 去重 | ✅ 零改动 | 逻辑通用 |
| 光晕 / 菜单栏 / 设置页框架 | ✅ 零改动 | UI 层与事件源解耦 |
| 文件监听（DispatchSource + readQueue + 健康检查 + 增量发布） | 🔧 抽象复用 | 从 `CursorHookAdapter` 抽参数化，指向不同事件文件 |
| 桥接脚本 | 🆕 新建 | `claude-bridge.sh`，字段映射与输出协议不同 |
| 安装/检测/合并 | 🆕 新建 | `ClaudeCodeSetupManager`，目标文件与结构不同 |

## 二、Claude Code hooks 协议要点

### 配置文件

- 用户级：`~/.claude/settings.json`
- 项目级：`.claude/settings.json`（本次接入建议只做用户级）

### 配置结构（三层嵌套，与 Cursor 两层不同）

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "/path/to/claude-bridge.sh", "args": [] }
        ]
      }
    ]
  }
}
```

- 第 1 层：事件名（`Stop`、`PreToolUse`…）
- 第 2 层：matcher 组（`"matcher": "*"` 匹配全部；工具事件可用 `Bash`、`Edit|Write` 等过滤）
- 第 3 层：hook handler（`type` + `command` + 可选 `args`）

### 事件名（大驼峰）

| Claude Code 事件 | 触发时机 | 对应 Cursor 语义 |
|---|---|---|
| `SessionStart` | 会话开始/恢复 | `sessionStart` |
| `SessionEnd` | 会话终止 | `sessionEnd` |
| `UserPromptSubmit` | 用户提交提示后 | `beforeSubmitPrompt` |
| `PreToolUse` | 工具调用前 | `preToolUse` |
| `PostToolUse` | 工具调用成功后 | `postToolUse` |
| `PostToolUseFailure` | 工具调用失败后 | `postToolUseFailure` |
| `SubagentStart` | 生成 subagent | `subagentStart` |
| `SubagentStop` | subagent 结束 | `subagentStop` |
| `Stop` | Claude 正常完成一轮 | `stop(status=completed)` |
| `StopFailure` | 轮次因 API 错误结束 | `stop(status=error)` |
| `Notification` | 发出通知 | （无直接对应，可忽略或映射 waiting） |

### stdin JSON 输入字段

通用字段（所有事件）：
- `session_id`、`prompt_id`、`transcript_path`、`cwd`、`permission_mode`、`hook_event_name`

事件专属字段：
- `PreToolUse`：`tool_name`、`tool_input`、`tool_use_id`
- `UserPromptSubmit`：`prompt`
- `SubagentStop`：`agent_id`、`agent_type`、`is_error`
- `Stop` / `StopFailure`：`stop_hook_active`（**无 `status` 字段**）

### stdout 协议（关键差异）

- Cursor：**必须**输出 `{"permission":"allow","continue":true}`，否则可能失败/重复。
- Claude Code：纯副作用 hook 只需 `exit 0`，**stdout 应静默**。stdout 输出 JSON 会被当作决策解析；输出纯文本（`UserPromptSubmit`/`SessionStart`）会被注入 Claude 上下文。
- 退出码：`0` 成功；`2` 阻塞（本接入不需要阻塞，仅日志）。

## 三、字段映射（Claude Code → 统一 HookEvent）

| Claude Code 字段 | 统一 HookEvent 字段 | 备注 |
|---|---|---|
| `hook_event_name` | `hook` | 值是大驼峰，如 `PreToolUse` |
| `session_id` | `conversationID` | |
| `prompt_id` | `generationID` | 每次 prompt 一个 UUID，恰好补 M4 所需会话内去重键 |
| `tool_use_id` | `taskID` / `toolUseID` | |
| `tool_name` | `toolName` | |
| `agent_id` | `subagentID` | |
| `is_error` | （判断用） | 用于 `SubagentStop` 状态判断 |
| `status` | — | Claude Code 无此字段，成功/失败由事件名区分 |

## 四、事件 → LiangState 映射（需在 `liangState` 加分支）

| Claude Code 事件 | LiangState |
|---|---|
| `SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `SubagentStart` | `processing` |
| `PostToolUseFailure` | `processing`（与 Cursor 一致） |
| `Stop` | `success` |
| `StopFailure` | `error` |
| `SubagentStop`（`is_error=true` / `false`） | `error` / `success` |
| `SessionEnd` | `idle` |

## 五、5 处本质差异（决定额外工作量）

| 维度 | Cursor | Claude Code |
|---|---|---|
| 配置文件 | `~/.cursor/hooks.json` | `~/.claude/settings.json` |
| 配置结构 | 两层 | **三层**（含 matcher + type） |
| 事件名 | 小驼峰 | 大驼峰 |
| stdout 协议 | 必须输出 JSON 响应 | 静默 exit 0 |
| 成功/失败区分 | `stop.status` 字段 | `Stop` vs `StopFailure` 两个事件；`SubagentStop.is_error` 布尔 |

## 六、必须注意的坑

1. **`~/.claude/settings.json` 绝不能整体覆盖**：除 `hooks` 外还有 `permissions`、`model`、`env`、`statusLine`、`outputStyle` 等大量用户配置。必须读取-合并-只改 `hooks`（复用 H2 修复的合并逻辑，但结构是三层）。
2. **安装检测方式不同**：Claude Code 是 CLI，检测用 `which claude` 或 `~/.claude` 目录存在，而非 bundle ID。
3. **stdout 静默**：`claude-bridge.sh` 的 `exit 0` 时 stdout 必须为空，不能照搬 Cursor 的 `{"permission":...}` 输出。
4. **matcher**：每个事件需 `"matcher": "*"`（或省略）才能捕获全部工具调用。

## 七、关于"自动安装"的澄清

- **安装 Claude Code 本体**（`claude` 命令）：❌ 不能自动，需用户自己 `npm install -g @anthropic-ai/claude-code`。它是 CLI 而非 GUI app，Liang 无从也无需代为安装。
- **配置桥接**（部署 `claude-bridge.sh` + 写 `~/.claude/settings.json`）：✅ 可一键自动，与 Cursor 的 `installAutomatically()` 对称。前提是 Claude Code 已装好。
- 这与 Cursor 现状完全对称：都是「检测到已安装 → 一键配置 hooks」，区别只在检测方式（bundle ID vs `which claude`）。

## 八、建议实施步骤（未开始）

1. 抽 `CursorHookAdapter` 文件监听为参数化（`id` + `eventsURL`），或新建 `ClaudeCodeAdapter` 复用读文件逻辑
2. 新建 `claude-bridge.sh`（stdin 读 Claude 格式 → 写统一 JSONL → 静默 exit 0）
3. `HookEvent` 加 `claudePayload` 解析 + `liangState` 加事件分支
4. 新建 `ClaudeCodeSetupManager`（`which claude` 检测 + 合并写入 settings.json）
5. 设置页 `CodingAgentPage` 加 Claude Code 页（`IDE` 枚举已预留 `claudeCode`）
6. Onboarding / 首次默认值按需补充

## 九、已确认决策

- **绿光停留逻辑沿用 Cursor**：Claude Code 的 `Stop → success` 复用 `GlowSettings.successMaxDuration`（默认 20s），不做独立参数。
- 事件文件：独立 `~/.liang/claude-events.jsonl`（避免与 Cursor 混淆）。

## 十、覆盖范围与边界（Claude Code 形态）

> 本节基于官方文档 `code.claude.com/docs/en/hooks`、`/desktop-quickstart`、`/cloud-environments` 核实，修正此前"Desktop app 不支持 hooks"的错误判断。

### 官方结论

官方 hooks 文档原文：

> "Hooks run wherever Claude Code runs: sessions in the terminal, IDE extensions, **the Desktop app**, and Claude Code on the web all fire the same hook events."

Desktop quickstart 文档进一步确认 Desktop 与 CLI **共享配置**：

> "Desktop runs the same engine as the CLI ... they share configuration (CLAUDE.md files, MCP servers, **hooks**, skills, and settings)."

**关键区分：决定 hooks 是否生效的不是"形态"，而是「会话类型」（本地会话 vs 云端会话）。**

### 覆盖矩阵

| Claude Code 形态 | 支持 hooks? | 读本地 `~/.claude/settings.json`? | 本机 shell 写 `~/.liang`? | Liang 覆盖? |
|---|---|---|---|---|
| macOS Terminal CLI（本地会话） | ✅ | ✅ | ✅ | ✅ 覆盖 |
| macOS VS Code 扩展（本地） | ✅ | ✅ | ✅ | ✅ 覆盖 |
| macOS JetBrains 扩展（本地） | ✅ | ✅ | ✅ | ✅ 覆盖 |
| macOS **Desktop app（本地会话）** | ✅ | ✅ | ✅ | ✅ 覆盖 |
| macOS **Desktop app（云端会话）** | ⚠️ 只跑仓库/组织 hooks | ❌ 不读用户级 | ❌ | ❌ 覆盖不到 |
| Claude Code **on the Web**（云端会话） | ⚠️ 只跑仓库/组织 hooks | ❌ 不读用户级 | ❌ | ❌ 覆盖不到 |
| iOS / 移动端（云端/远程） | 视会话类型 | ❌ | ❌ | ❌ 覆盖不到 |
| VS Code **Remote SSH / WSL / Dev Container** | ✅ 但跑在远程 | ❌ 读远程配置 | ❌ 写远程 `~/.liang` | ❌ 覆盖不到 |

### 核心机制：本地会话 vs 云端会话

1. **本地会话**（Terminal CLI、本地 IDE 扩展、Desktop app 的本地会话）：
   - 读取用户级 `~/.claude/settings.json`（含 hooks），hook 命令在本机 shell 执行，写本机 `~/.liang`，Liang 能收到。
   - 这些形态与 Cursor 接入完全同构，一套桥接脚本全覆盖。

2. **云端会话**（Claude Code on the web、Desktop app 从云启动的会话、`claude --cloud`）：
   - **不读取**本地 `~/.claude/settings.json`（官方原文："Cloud sessions ... don't read your local `~/.claude/settings.json`"）。
   - 只运行仓库 `.claude/settings.json` 里的 hooks + 组织 server-managed 下发的 hooks。
   - 会话跑在 Anthropic 托管 VM 上，hook 命令写的是远端文件系统，本机 Liang 收不到。

### 与本次问题的对应关系

- 之前实测「Desktop app 无事件进来、CLI 装好后有事件」，是因为 **Desktop app 当时运行的是云端会话**（云端不读本地用户级 settings.json），而非 Desktop 本身不支持 hooks。改用本地 CLI 后命中本地会话，事件正常流入。
- 因此接入边界不是"Desktop 不支持"，而是"**本地会话能覆盖，云端会话覆盖不到**"。这与 Liang 本机 app 的定位一致。

### 订阅要求（重要）

官方 `desktop-quickstart` 原文：

> "Claude Code requires a Pro, Max, Team, or Enterprise subscription."
> "If clicking Code prompts you to upgrade, you need to subscribe to a paid plan first."

- **Desktop app 三个 tab**：Chat（对话，无文件访问）、Cowork（异步云端代理，跑远程 VM）、Code（本地交互式编码，访问本地文件）。
- **Code tab 本地会话需要付费订阅**（Pro/Max/Team/Enterprise）。免费版点击 Code 会提示升级，**无法使用本地会话**，因此也无法在 Desktop 里触发本地 hooks。
- **免费版能用 Chat 与 Cowork**，但 Cowork 是云端会话（跑远程 VM，不读本地用户级 settings.json，不触发本地 hooks）。
- **结论**：免费版用户只能通过 **CLI 路径**验证本地 hooks；Desktop 本地会话需付费订阅后才有入口。二者共享同一 `~/.claude/settings.json` 与引擎，hooks 行为一致。

### 版本要求

官方文档未给 Desktop app 运行 hooks 的最低版本门槛——Desktop app 内置 Claude Code 引擎，与 CLI 共享 hooks 能力，无需额外安装 CLI。文档仅标注了通用功能版本差异（如 v2.1.191 matcher 逗号分隔、v2.1.196 增加 `prompt_id` 字段），均非 Desktop 的准入条件。

### 待实测项

- Desktop app **本地会话**（需付费订阅）下 hooks 是否如文档所述读取 `~/.claude/settings.json`：付费后可实测确认（免费版无 Code tab 入口，无法验证）。用户已确认 Terminal CLI 路径正常，核心链路已验证。
- `prompt_id` 字段（本桥接脚本用作 `generation_id`）需 Claude Code ≥ v2.1.196；更低版本该字段可能缺失，但 `session_id` 仍可保证基本去重。
