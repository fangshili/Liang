# DeepSeek Harness 接入调研（暂不集成）

> 调研日期：2026-08-24。状态：仅调研存档，暂不开发。DSH 仍处于 v0.1 开发者预览，事件 API 可能变化。

## 结论

1. **能接入**，但必须是「桥接」架构，不是把 Liang 直接塞进 DSH。
2. **当前 app 集成**，不需要独立版本；DSH 作为第 5 个 agent 源（Cursor / Claude Code / Codex / CodeBuddy / DSH）。

## DeepSeek Harness 是什么

- DeepSeek 开源的 Agent 运行编排框架，8/13 发布 v0.1 开发者预览版，MIT 协议，主打「一切皆插件」。
- 插件是 TypeScript 模块，导出 `apply(ctx)`，运行在 Node.js 进程（底层 Cordis 依赖注入框架，Koishi 那套）。
- 插件能力 9 大类：models / tools / skills / sessions / sandboxes / storage / loops / scheduling / UI。

## 核心矛盾与桥接架构

DSH 插件是 TS 代码跑在 Node.js 里，**做不了 macOS 原生光晕**（刘海/光标/菜单栏）。而 Liang 的价值恰恰是原生光晕。

因此正确架构是桥接，与 Liang 现有 hooks 机制完全同构：

```
DSH 插件(TS)                       Liang 原生 App
   │ 订阅 session/event 事件流        │
   │ 归一化写 ~/.liang/dsh-events.jsonl ──→ FileHookAdapter 监听 ──→ StateEngine ──→ 光晕
```

## 已确认的事件能力（接入前提）

DSH 插件能拿到 agent 事件（已查实）：

- **Cordis 实时事件**：`agent/step`、`agent/request`、`agent/request-error`、`tools/result`、`session/event`
- **持久化会话事件**（监听 `session/event` 后检查 `event.type`）：`tool/call`、`tool/result`、`turn/*`（含 `turn/start`）、`step/*`、`compaction/*`
- **社区先例**：Litefuse 可观测插件即订阅 `session/event` 流获取执行过程。

监听方式示例：

```ts
ctx.on('session/event', (event) => {
  if (event.type === 'tool/call') { /* ... */ }
  else if (event.type === 'tool/result') { /* ... */ }
  else if (event.type.startsWith('turn/')) { /* ... */ }
})
```

## 接入方式（唯一正确做法）

DSH **没有** Cursor/Claude 那种独立的 `hooks.json` 机制，但 Cordis 事件流是等价能力。所以：

> 写一个 DSH 插件（TS），订阅 `session/event`，把事件归一化写到 `~/.liang/dsh-events.jsonl`，其余全部复用现有 Liang 逻辑（FileHookAdapter + StateEngine + SetupManager + SetupSection + Page + HeroCard）。

用户侧体验：`dsh plugin add liang` 装插件 → Liang 设置里看到 DSH → 一键启用。

## 事件映射（初步，待实测校准）

| DSH 事件 | Liang 状态 |
|---|---|
| `agent/request` / `turn/start` | processing |
| `tool/call` | processing（≈ PreToolUse） |
| `tool/result` | processing（≈ PostToolUse） |
| `turn/*` 结束 / agent 完成 | success |
| `compaction/*` | 忽略 |

## 待确认点（正式开发前）

1. **是否有明确的「会话开始/结束」「任务成功/失败」事件**——目前只确认 `turn/start`、`tool/call`、`tool/result`，完整 `turn/*` 子事件列表和 status 字段未知。这决定能否像 Claude 那样区分成功/失败（大概率又是「恒 success」，与 Codex/CodeBuddy 一致）。
2. **DSH 插件能否自由写文件**（Node.js `fs`）——几乎肯定能，但需确认 DSH 是否对插件有沙箱限制。
3. **`session/event` 事件对象的完整字段**（session_id、tool_name、status 等）——需实测。

## 开发时的流程（参考 CodeBuddy 接入）

1. 装一个 DSH，写最小 dump 插件抓一份 `session/event` 事件样本，确认字段。
2. 照抄现有「SetupManager + bridge + FileHookAdapter + SetupSection + Page + HeroCard + I18n」模式。
3. 安装检测：DSH 的 `dsh` CLI（类似 codebuddy 的多路径检测）。
