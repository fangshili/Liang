# Liang 代码评审报告：v0.1.7 – v0.1.8（CodeBuddy 集成 + Agent 检测修复）

> 评审日期：2026-08-24（二次修订，含真机实测证据）
> 评审范围：提交 `52413f2`（v0.1.7 防止启用/配置未安装的 agent）与 `f504a44`（v0.1.8 CodeBuddy 集成）
> 覆盖文件：CodeBuddySetupManager / CodeBuddySetupSection / codebuddy-bridge.sh / SettingsView / OnboardingView / GlowSettings / I18n / FileHookAdapter / IDE / docs

---

## 0. 验证基线

以下事实为本报告结论的取证基础：

| 验证项 | 结果 | 方式 |
| --- | --- | --- |
| 编译 | `swift build -c debug` 通过，无编译错误 | 本机执行 |
| 桥接脚本两份副本 | `hooks/` 与 `Sources/Liang/Resources/hooks/` 逐字节一致（codebuddy/claude/liang） | `diff` |
| CodeBuddy hooks 协议 | 官方文档确认：stdin 传 JSON、字段 `hook_event_name` / `session_id`；配置为三层嵌套 `hooks → 事件 → [{matcher, hooks:[{type, command}]}]` | [官方 Hook 参考指南](https://www.codebuddy.cn/docs/cli/hooks) |
| `matcher: "*"` 合法性 | 官方文档明确 `*` / 空串 / 省略三种写法均匹配全部工具 | 同上 |
| 时间戳解析 | 本地实验：`ISO8601DateFormatter`（`.withFractionalSeconds`）可解析 Python `isoformat()` 的 6 位微秒格式；仅当微秒恰为 0（约百万分之一概率）时回退 `Date()`，无实际影响 | Swift 实验 |
| 真机集成效果 | `~/.codebuddy/settings.json` 已写入 7 个事件的桥接配置；`~/.liang/codebuddy-events.jsonl` 已有约 95 条真实事件（preToolUse×39 / postToolUse×39 / stop / sessionStart 等），**hooks 安装后即生效、无审核提示** | 本机实测 |

---

## 1. 发现总览

| # | 严重度 | 标题 | 位置 |
| --- | --- | --- | --- |
| F3 | **High** | 桥接脚本把环境变量明文转储到无上限日志（真实凭据已落盘） | `Resources/hooks/codebuddy-bridge.sh:15-19`（claude/codex 同款） |
| F1 | Medium | CodeBuddy 安装后 UI 显示「已配置」，但运行中的会话可能不生效（条件性） | `CodeBuddySetupManager.swift:106-125` |
| F2 | Medium | 静态检测「已配置」误报：任意非空 command 都算命中 | `CodeBuddySetupManager.swift:149-188` |
| F4 | Medium | 打开「编码 Agent」设置页会静默关闭正在工作的集成 | `SettingsView.swift:443-453` |
| F5 | Medium | 桥接事件集与官方文档矛盾：漏掉 PostToolUseFailure / SubagentStart / StopFailure | `codebuddy-bridge.sh:50-59` |
| F6 | Low | CodeBuddy 事件缺 `tool_use_id`，任务只能到会话/回合粒度 | `codebuddy-bridge.sh:70-80` |
| F7 | Low | 多 IDE 共享同一状态机，CodeBuddy 恒 success 加剧状态闪烁 | `StateEngine.swift:61-96` |
| N1/N2 | Nit | `hasCompletedCodeBuddySetup` 只写不读；Onboarding 卡片不展示安装错误 | `OnboardingWindowController.swift:75` |

---

## 2. 详细发现

### F3（High）— 桥接脚本把环境变量明文转储到无上限日志（真实凭据已落盘）

**位置**：`Sources/Liang/Resources/hooks/codebuddy-bridge.sh:15-19`（v0.1.8 新增）；`claude-bridge.sh:15-19`、`codex-bridge.sh:15-19` 同款模式，共享同一日志文件。

**问题**：每次 hook 触发都会执行：

```bash
env | grep -Ei 'CODEBUDDY|HOOK|AGENT|TENCENT' | sort >> "$ENV_PATH"   # ~/.liang/bridge-env.log
```

且 `bridge-debug.log` 每事件追加 2 行。两个文件**无大小上限**、默认权限 **0644**，且所有桥接脚本共用同一文件。

**真机证据（本机实测）**：

- `~/.liang/bridge-env.log` 已达 **38.2 MB**（约一个月累积：Cursor 17850 次、Claude 1450 次、CodeBuddy 224 次转储），`bridge-debug.log` 3.1 MB；
- 明文包含 **`ANTHROPIC_AUTH_TOKEN=sk-842…`（真实 Claude API key）**、多个 `CLAUDE_CODE_MESSAGING_TOKEN=…`、`CURSOR_USER_EMAIL=…`；
- 新增的 codebuddy 桥接 grep 会匹配 `CODEBUDDY_*` / `TENCENTCLOUD_*` 前缀的凭据（如 `TENCENTCLOUD_SECRETID/SECRETKEY`），是新的泄露面。

**影响**：a) **凭据泄露**——API key / token 以明文写入本地普通日志文件，同机其他本地用户/进程可读，一旦主目录被同步或分享诊断信息即外泄；b) **磁盘无界增长**——按当前速率约 400MB/年，低磁盘机器长期受影响；c) 与脚本头「不转发 prompt、代码、文件内容」的隐私承诺相悖（它没转发这些，但转发了环境变量）。

**修复建议**：

```bash
# 1) 删除 env 转储，或只记录变量名不记录值：
env | grep -Ei 'CODEBUDDY|HOOK|AGENT|TENCENT' | cut -d= -f1 | sort >> "$ENV_PATH"
# 2) 正常事件不写 debug 日志，仅错误路径写 error 日志；
# 3) 对日志做大小轮转（如超 1MB 截断）。
```

### F1（Medium，二次修订）— CodeBuddy 安装后 UI 显示「已配置」，但运行中的会话可能不生效

**位置**：`Sources/Liang/CodeBuddySetupManager.swift:106-125`（`installAutomatically`）、`CodeBuddySetupSection.swift:37-59`、`I18n.swift:371/708`（`codebuddyInstallConfirmMessage`）。

**问题**：安装流程写入 `~/.codebuddy/settings.json` 后立即 `performStaticCheck()` 返回 `.configured`，UI 显示绿色「已连接」。但 [官方文档「配置安全」](https://www.codebuddy.cn/docs/cli/hooks) 说明外部修改 hooks 的生效分两条路径：

- **启动时捕获快照**：CodeBuddy 未运行时安装 → 下次启动的新快照直接包含新 hooks → **立即生效，无审核提示**（本机实测场景，确认成立）；
- **运行中外部修改**：安装时 CodeBuddy 正在运行 → 当前会话继续使用旧快照，CodeBuddy 会发出警告，**需在 `/hooks` 菜单审查后才能应用**，或重启会话。

Liang 的确认弹窗、设置页、Onboarding 卡片均无任何关于此条件的提示。

**影响**：若用户在 CodeBuddy 运行期间安装（开发者常见场景：正在用 CodeBuddy 时顺手配置 Liang），会看到绿色「已配置」+ 状态点绿色（FileHookAdapter 一启动即 `isConnected=true`），但事件不流入，光晕无反应，且无任何指引。**触发面为条件性，非必然失败**。

**修复建议**：安装成功后追加条件性提示，并预置到确认文案中：

> 配置已写入。若 CodeBuddy 正在运行，请在 CodeBuddy 中打开 `/hooks` 审查应用更改，或重启会话使其生效。

同时可在 `docs/codebuddy-integration.md` 限制 3 处补充 UI 提示的对应说明。

### F2（Medium）— 静态检测「已配置」误报：任意非空 command 都算命中

**位置**：`Sources/Liang/CodeBuddySetupManager.swift:149-188`（`performStaticCheck`）。

**问题**：检测只要求每个事件存在**任意**非空 `command`，不校验其是否指向 Liang 的桥接脚本：

```swift
for handler in handlers {
    if let cmd = handler["command"] as? String, !cmd.isEmpty {
        if scriptPath == nil { scriptPath = resolveScriptPath(cmd) }  // 取第一个 command
        found = true
        break
    }
}
```

若用户在 `~/.codebuddy/settings.json` 配置了自己的 hooks（command 为存在的可执行文件绝对路径），Liang 会把**用户的脚本**解析为 `scriptPath` 并判定 `.configured`，即使 `codebuddy-bridge.sh` 并未安装。

**影响**：检测结果不可信——误报「已连接」且脚本路径可能指向用户自己的脚本；与 F1 叠加会出现「两处显示成功、事件就是不出现」。同样逻辑存在于 `ClaudeCodeSetupManager.swift:152-191` 与 `CodexSetupManager.swift:156-195`（旧代码），本提交新增的 CodeBuddy 应带头修正并统一三处。

**修复建议**：命中条件改为「command 标准化路径 == `defaultScriptURL.path`（或 basename 为 `codebuddy-bridge.sh`）」：

```swift
let isLiang = (cmd as NSString).standardizingPath == defaultScriptURL.path
    || (cmd as NSString).lastPathComponent == "codebuddy-bridge.sh"
if isLiang { found = true; if scriptPath == nil { scriptPath = resolveScriptPath(cmd) } }
```

### F4（Medium）— 打开「编码 Agent」设置页会静默关闭正在工作的集成（v0.1.7 引入）

**位置**：`Sources/Liang/SettingsView.swift:443-453`（`refreshInstallationState`），挂载于 `.onAppear`（第 334-336 行）。

**问题**：v0.1.7 新增逻辑在页面**每次出现**时检测各 agent 安装状态，检测失败即强制关闭：

```swift
if !cursorManager.isCursorInstalled { settings.setIDEEnabled(.cursor, enabled: false) }
if !claudeManager.isClaudeCodeInstalled { settings.setIDEEnabled(.claudeCode, enabled: false) }
if !codexManager.isCodexInstalled { settings.setIDEEnabled(.codex, enabled: false) }
if !codeBuddyManager.isCodeBuddyInstalled { settings.setIDEEnabled(.codeBuddy, enabled: false) }
```

而检测依赖固定路径列表（Cursor 仅 `/Applications`、`~/Applications` + LaunchServices；CLI agent 仅 homebrew/npm-global/nvm/local 等）。未覆盖的常见安装方式：pnpm（`~/Library/pnpm`）、volta（`~/.volta/bin`）、fnm 等。

**影响**：用户**只是打开设置页**，工作正常的集成就被静默关闭并持久化（autosave 0.3s 写盘），光晕从此无响应且无任何提示。属「防止启用未安装 agent」目标的副作用：它同时会**关闭已启用的**。

> 注：本机 codebuddy 位于 `~/.nvm/versions/node/v22.17.0/bin/codebuddy`（nvm 路径已覆盖），故本机未触发；但 pnpm/volta 用户会踩中。

**修复建议**：`.onAppear` 只刷新检测状态用于 UI（禁用开关、「未安装」角标），**不要**在页面出现时改 `ideEnabled`；仅在用户主动开启开关时拦截（toggle setter 已有该逻辑）。检测失败时提示「未检测到，请确认安装路径」，并补充 pnpm/volta/fnm 等常见路径。

### F5（Medium）— 桥接事件集与官方文档矛盾：漏掉 PostToolUseFailure / SubagentStart / StopFailure

**位置**：`Sources/Liang/Resources/hooks/codebuddy-bridge.sh:50-59`（EVENT_MAP）、`CodeBuddySetupManager.swift:74-82`（requiredHooks）、`docs/codebuddy-integration.md:42-43`。

**问题**：代码注释与集成文档声称「CodeBuddy 无 SubagentStart / PostToolUseFailure / StopFailure 事件」，但官方文档明确列出事件家族包含 `PostToolUseFailure`、`SubagentStart`、`SubagentStop`、`StopFailure`（「完整支持 Hook 事件家族（27+ 种）…」）。两者矛盾，注释依据存疑。

**影响（若这些事件真实存在）**：

- `PostToolUseFailure` 被忽略 → 工具失败时状态停留在 processing 直到 60s 超时，光晕长时间卡在「工作中」而非红色错误；
- `StopFailure` 缺失 → 任务失败恒显示成功（绿色），误导用户；
- `SubagentStart` 缺失 → 子代理启动不可见。

**验证状态**：本机约 95 条事件中未出现上述事件（也无子代理使用场景），无法定论。建议真机触发一次「子代理任务」和「工具失败」验证后补齐映射。

**修复建议**：按官方文档补齐事件映射（`PostToolUseFailure → postToolUseFailure`，`StopFailure → stop + status=error`，`SubagentStart → subagentStart`）；若确无此事件，改写注释与文档避免与官方文档正面矛盾。

### F6（Low，二次修订）— CodeBuddy 事件缺 `tool_use_id`，任务只能到会话/回合粒度

**位置**：`Sources/Liang/Resources/hooks/codebuddy-bridge.sh:70-80`。

**问题**：桥接输出 `tool_use_id` 对 CodeBuddy 恒为 null（本机事件文件确认）。**修订**：`generation_id` 实际存在（本机事件可见 `"generation_id": "d0da87f6…"`），与此前按文档示例推断的「恒 nil」不符；缺失的只有 `tool_use_id`。

**影响**：`HookEvent.taskID` 为空，`StateEngine.updateRecentTasks`（`StateEngine.swift:390`）只能按 conversationID+generationID 归并任务；任务标题粒度从工具级退化为会话/回合级，且去重签名（`StateEngine.swift:340-352`）变弱。非阻塞性。

**修复建议**：按会话 + 回合 + 工具名构造本地 taskID，或在文档限制中说明该差异。

### F7（Low）— 多 IDE 共享同一状态机，CodeBuddy 恒 success 加剧状态闪烁

**位置**：`Sources/Liang/StateEngine.swift:61-96`、`HookEvent.swift:71-75`。

**问题**：4 个 adapter 的事件不加来源过滤地汇入同一全局状态机。CodeBuddy 安装即自动启用（`CodeBuddySetupManager.swift:116`），且 `SubagentStop`/`Stop` 恒映射 `completed → success`（已文档化的限制）。多 agent 并行时：a) 不同 agent 的事件互相覆盖全局状态；b) CodeBuddy 子代理结束时全局状态闪成绿色 success，直到下一条事件切回。

**影响**：多 agent 并行时光晕状态不可信、闪烁。属既有设计局限，v0.1.8 新增第 4 个来源使其更易触发。

**修复建议**：`HookEvent.liangState` 中对 `subagentStop` 不做全局 success 提升，或按 source 隔离状态机。

### Nit

- **N1**：`hasCompletedCodeBuddySetup` 只写不读（`OnboardingWindowController.swift:75` 写入，`GlowSettings` 全链路持久化，无 UI 读取）。死状态，建议注释说明用途。
- **N2**：Onboarding 卡片（`OnboardingView.swift` 的 `CodeBuddyHeroCard`）不展示 `lastInstallError`；安装失败时用户点击后看不到任何反馈（Cursor/Claude 卡片同样，非本次引入）。

---

## 3. 已验证排除项（避免误报）

- **时间戳解析**：6 位微秒可解析；仅微秒为 0 时（约百万分之一概率）解析失败回退 `Date()`，不影响体验。
- **`matcher: "*"`**：官方文档明确为合法「匹配全部」写法。
- **payload 传递**：官方文档确认 hooks 经 stdin 传 JSON，`hook_event_name` / `session_id` 字段名正确，桥接读取方式无误。
- **构建**：`swift build -c debug` 通过。
- **桥接副本一致性**：两份副本逐字节一致。
- **真机端到端**：安装 → settings.json 写入 → CodeBuddy 触发 → 事件落盘全链路正常（无需 /hooks 审核，见 F1）。

---

## 4. 修复优先级

1. **F3（High）**：删除/脱敏 env 转储 + 日志轮转 —— 真实凭据已落盘，建议立即处理；
2. **F1（Medium）**：安装后条件性提示「CodeBuddy 运行中请 /hooks 审核或重启会话」——低成本高收益；
3. **F2（Medium）**：静态检测校验 command 必须指向桥接脚本，并统一 Claude/Codex/CodeBuddy 三处；
4. **F4（Medium）**：设置页 `.onAppear` 不再静默修改 `ideEnabled`，仅拦截用户主动开启；
5. **F5（Medium）**：真机验证 PostToolUseFailure/SubagentStart/StopFailure 后补齐事件映射；
6. **F6 / F7 / N1 / N2**：按后续迭代处理。

---

## 5. 总结

v0.1.8 的 CodeBuddy 集成整体结构清晰、与既有模式一致，官方协议核对（stdin JSON、配置结构、matcher 语义）方向正确，且经真机验证安装后即生效、事件正常流入。核心问题集中在两点：**桥接脚本的 env 明文转储（F3，已有真实凭据泄露）** 与 **「假装成功」型 UX 缺陷（F1 条件性、F2 误报）**。修复上述问题后，本版本可视为健康。
