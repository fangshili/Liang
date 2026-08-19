# Liang 代码审查报告

> 审查日期：2025-08-17
> 审查范围：`Sources/Liang/*.swift`（约 8000 行）、`hooks/*.sh`、`scripts/*.sh`、`Package.swift`、`docs/cursor-hooks.md`
> 验证情况：`swift build --disable-sandbox` 编译通过；所有 shell 脚本通过 `bash -n` 语法检查；桥接脚本字段名（`hook_event_name`、`conversation_id`、`generation_id`、`tool_use_id`、`subagent_id`、`status`、`failure_type`、`duration_ms`）与 [Cursor 官方 Hooks 文档](https://cursor.com/docs/hooks.md) 核对一致。
> 结论：结构清晰、分层合理，但存在 2 个严重问题、7 个中等问题，建议按"严重 → 中"顺序修复。
> 二次核对补充：H1 与 M1 合并为一处修复；M4 需并入 `generationID`；M7 需跳过 heartbeat；新增 2 个低优先级 S1（success 被 sessionEnd 覆盖，影响极小不建议修）、S2（restart 事件重放）。详见第五节。

---

## 〇、修复验证结果（2026-08-18 复核）

> 复核方式：`git diff` 逐条核对 + `swift build --disable-sandbox` 编译通过 + `bash -n` 全脚本通过 + 用临时 `$HOME` 实测 bridge/install/uninstall。**全部 High + Medium 均已正确修复。**

| 编号 | 状态 | 验证结论 |
|---|---|---|
| **H1** | ✅ 已修复 | `CursorHookAdapter` 移除 `@Published events`，改 `PassthroughSubject<HookEvent>` 逐条发布；`StateEngine` 订阅 `eventSubject` 逐条 `handle`。已无任何残留 `$events` / `events.last` 引用，编译通过。 |
| **H2** | ✅ 已修复 | Swift `performInstall` 与 `install.sh` 改为按事件名**合并**（保留 `version`、其他工具条目、额外顶层字段）；`uninstall.sh` 仅移除 Liang 条目、非空时保留文件。实测：预置 `version=2` + `customTopLevel` + `other-tool` 条目，install 后三者保留、Liang 条目 append；uninstall 后仅剩 other-tool 条目，桥接脚本正确删除。 |
| **M1** | ✅ 已修复（与 H1 合一） | 无界 `events` 数组已删除，无内存增长路径。 |
| **M2** | ✅ 已修复 | 新增串行 `readQueue`，DispatchSource queue 改为 `readQueue`，健康检查的大小比较/追读也 dispatch 到 `readQueue`，消除并发读同一 `FileHandle`。⚠️ 小提醒见下。 |
| **M3** | ✅ 已修复 | `transition(to:conversationID:)` 增加会话过滤；`handle` 传入 `event.conversationID`；超时/心跳等无会话 ID 时回退全部更新。 |
| **M4** | ✅ 已修复 | `isDuplicate` 签名并入 `conversationID` + `generationID`。 |
| **M5** | ✅ 已修复 | `load()` 补回 `notchExpansionEnabled` 与 `cursorLabelEnabled`。 |
| **M6** | ✅ 已修复 | 两份 `liang-bridge.sh` 改为 payload 走 stdin（`sys.stdin.read()`），删除 `PAYLOAD=$(cat)`；实测 500KB payload 正常写入事件文件并输出正确 JSON 响应。 |
| **M7** | ✅ 已修复 | `start()` 先 `bindSettings()` 再判断 `cursorHooksEnabled`：false 时不启动 adapter、不启动 heartbeat，直接 `transition(to: .disconnected)`。 |

**M2 小提醒（不影响"已修复"结论）**：`CursorHookAdapter.swift:86` 的事件 handler 现在读 `self.fileHandle`，而 `fileHandle` 在 `start()`（第 97 行）才赋值、且 `resume()` 在第 95 行先执行——极端情况下存在 `resume` 后、`fileHandle` 赋值前 `.extend` 触发导致 handler 读 nil 的极小窗口（该次事件最多延迟 30s 由健康检查补读，不会丢失）。若想彻底消除，把 `self.fileHandle = handle` 移到 `newSource.resume()` 之前即可。

**未修复（维持 Low / Nit，经确认暂不处理）**：S1、S2、L1–L8、Nit 系列。

---

## 一、严重问题（High）

### H1. 批量到达的事件只处理最后一条，中间事件被静默丢弃 ✅ 已修复

- **位置**：`Sources/Liang/CursorHookAdapter.swift:179-186`（批量 append）+ `Sources/Liang/StateEngine.swift:62-68`（只取 `events.last`）
- **问题**：`readAvailableLines` 把一次读取到的所有行通过 `events.append(contentsOf:)` 一次性追加，`@Published` 只发布一次；`StateEngine` 的订阅者执行 `guard let event = events.last else { return }; self.handle(event: event)`，**同一批次中除最后一条外的所有事件都不会进入状态机**。
- **触发场景**：Cursor 的 hook 顺序触发，多条事件可能在毫秒级连续写入并被 DispatchSource 合并为一次 `.extend` 事件。典型如：
  - `stop(status=completed)` + `sessionEnd` 同批 → 只处理 `sessionEnd` → **success 绿色闪光被整体跳过**，光晕直接从 processing 回 idle；
  - `sessionStart` + `beforeSubmitPrompt` 同批 → 只处理后者；
  - `preToolUse` + `postToolUse` 同批 → 两者都映射 processing，肉眼无差别（所以大部分时候感知不到）。
- **影响**：光晕/任务列表可能跳过真实发生过的状态，与 Cursor 实际运行状态不匹配；这是确定性逻辑缺陷，非偶发竞态。
- **修复方案**（推荐，与 M1 合并为同一改动，见 M1）：让 adapter 改为**发布增量**，StateEngine 订阅增量逐条 `handle`，彻底消除"数组整体替换→只取 last"的错位，也顺带解决 M1 的无界增长。原报告主方案用 `processedEventCount` 游标追踪数组，一旦按 M1 裁剪/改增量，游标就会错位，故不采纳游标方案。

```swift
// CursorHookAdapter 中：events 数组改为只做 UI 展示用，另加增量发布
let eventSubject = PassthroughSubject<HookEvent, Never>()
// readAvailableLines 解析出新事件后，逐条：
//   DispatchQueue.main.async { self.eventSubject.send(e) }
// StateEngine 中：
adapter.eventSubject
    .receive(on: DispatchQueue.main)
    .sink { [weak self] event in self?.handle(event: event) }
    .store(in: &cancellables)
```

  **注意（重要，原报告未覆盖）**：即使逐条处理，`stop(status=completed)` + `sessionEnd` 同批场景下，success 仍会被紧随的 `sessionEnd → idle` **立即覆盖**（`transition(to: .idle)` 会 `invalidateTimers()`，success 的 `successResetTimer` 被取消）。绿色闪光依旧几乎不可见。这是独立于丢事件的**状态机语义问题**，详见文末"重新审视补充 S1"。

### H2. 自动安装 / 卸载会覆盖或删除用户已有的 `~/.cursor/hooks.json` ✅ 已修复

- **位置**：`Sources/Liang/CursorSetupManager.swift:231-240`（`performInstall` 全量覆盖写入）；`hooks/install.sh:25-46`；`hooks/uninstall.sh:11-12`
- **问题**：`performInstall` 用 Liang 自己的 hooks 字典**整体替换** `~/.cursor/hooks.json`，不读取/合并已有配置；`uninstall.sh` 直接 `rm -f` 整个 hooks.json。若用户此前配置过其他工具/插件的 Cursor hooks，会被静默抹掉。
- **影响**：数据丢失。App 内确认弹窗（`.installConfirmMessage`）已声明"替换现有配置"，但 CLI 脚本 `install.sh` 无任何提示，`uninstall.sh` 更是删除整个文件而非只移除 Liang 条目。
- **修复方案**：
  1. `performInstall` 先读取现有 hooks.json，按事件名合并：对每个 `requiredHooks` 事件，将 Liang 的 command **append 到已有命令数组末尾**（而非覆盖该事件名下的其他工具条目），保留用户既有条目；
  2. `uninstall.sh` 不能只靠字面"删引用"——需用 Python/`jq` 解析 JSON，从每个事件的命令数组中移除指向 `liang-bridge.sh` 的条目，并删除变为空的键；仅当整个 `hooks` 字典为空时才删除 `hooks.json`，否则保留文件。

---

## 二、中等问题（Medium）

### M1. `CursorHookAdapter.events` 数组无界增长（内存泄漏） ✅ 已修复

- **位置**：`Sources/Liang/CursorHookAdapter.swift:16, 179-186`
- **问题**：每次读取都 `events.append(contentsOf:)`，数组从不裁剪。`StateEngine.recentTasks` 有 50 条上限，但 `events` 没有；每条事件还持有 `rawPayload` 字典。长会话可积累数万条事件。
- **影响**：内存持续增长；每次 append 触发 `@Published` 发布，设置页 `CursorPage` 的 `@ObservedObject adapter` 随之整体重绘（已核实 `SettingsView.swift:409` 确实以 `@ObservedObject` 持有 adapter）。
- **修复方案**（与 H1 合并，一处改动解决两问题）：adapter 改为发布增量（`PassthroughSubject<HookEvent>`），StateEngine 订阅增量逐条处理；`events` 数组保留但仅用于「最近事件」展示并加裁剪（如保留 500 条），或干脆移除不再需要的数组。

### M2. DispatchSource 与健康检查并发读同一 FileHandle 存在竞态 ✅ 已修复

- **位置**：`Sources/Liang/CursorHookAdapter.swift:79-82`（utility 并发队列 `.extend` handler）vs `141-144`（主线程 30s 定时器健康检查）
- **问题**：两条路径都对同一个 `FileHandle` 调用 `readToEnd()` 并更新共享 `lastReadOffset`（无锁）。`readToEnd` 是多次 `read()` 的循环，两线程交错时一条 JSONL 行可能被拆到两次读取，各自 JSON 解析失败 → **该事件永久丢失**（offset 已越过）。
- **影响**：偶发事件丢失，且不报错。
- **修复方案**：文件读取收敛到单一串行队列；或健康检查只比较文件大小、通过向 source 发信号触发读取，不再直接读文件。

### M3. 状态传播（transition 兜底）不区分会话，污染并行会话的任务状态 ✅ 已修复

- **位置**：`Sources/Liang/StateEngine.swift:169-186`
- **问题**：`transition(to:)` 中 `for index in recentTasks.indices where recentTasks[index].state == previousState` 会把**所有**处于前一状态的任务改成新状态，不看 `conversationID`。并行会话场景：会话 A 完成（`stop → success`）时全局状态是 processing（B 仍在跑），传播循环会把 B 的任务也标成 success；B 若处于长思考期（数分钟无事件），任务卡和光晕状态都会错误显示。
- **修复方案**：把触发事件的 `conversationID` 传入 `transition`，只更新匹配会话的任务；会话 ID 缺失时再回退到"全部更新"。

### M4. 去重签名不含 conversation_id，跨会话事件被误去重 ✅ 已修复

- **位置**：`Sources/Liang/StateEngine.swift:291-303`
- **问题**：签名 `"\(event.hook)|\(event.taskID ?? "")|\(event.status ?? "")"`。`beforeSubmitPrompt`、`sessionStart` 等事件 `taskID` 恒为空，签名退化为 `"beforeSubmitPrompt||"`。默认去重窗口 1 秒内，**两个不同会话的同类事件、或同一会话的两次连续提交**都会被当作重复丢弃；两个会话先后在 1 秒内 `stop(completed)` 时第二个 stop 被丢弃（该任务卡永远停在 processing）。
- **修复方案**（原方案不完整，需补强）：只加 `conversationID` 只能消除**跨会话**误去重；报告自列的"同一会话的两次连续提交也会被误去重"依然存在——两次提交 `conversationID` 相同，签名仍相同。需同时并入**每次提交都会变化的 `generationID`**：

```swift
let signature = "\(event.hook)|\(event.conversationID ?? "")|\(event.generationID ?? "")|\(event.taskID ?? "")|\(event.status ?? "")"
```

  若个别 hook（如 `sessionStart`/`sessionEnd`）连 `generationID` 也缺失，签名仍可能退化为 `"hook||||"`；彻底兜底用原始 `rawPayload` 的内容哈希作为最后一段。

### M5. `GlowSettings.load()` 漏恢复两个持久化字段 ✅ 已修复

- **位置**：`Sources/Liang/GlowSettings.swift:268-306`（对照 `encode` 178-179 行、`init(from:)` 123-125 行）
- **问题**：`encode` 与 `init(from:)` 都包含 `notchExpansionEnabled` 和 `cursorLabelEnabled`，但 `load()` 手工逐字段拷贝时漏掉了这两个 → 重启后无条件恢复默认 `true`。
- **影响**：用户关闭"光标状态标签"或"刘海展开面板"后，重启应用即静默失效。
- **修复方案**：在 `load()` 中补上 `notchExpansionEnabled = loaded.notchExpansionEnabled`、`cursorLabelEnabled = loaded.cursorLabelEnabled`。

### M6. 桥接脚本用 argv 传递完整 payload（ARG_MAX 溢出 + 进程参数可见） ✅ 已修复

- **位置**：`Sources/Liang/Resources/hooks/liang-bridge.sh:23, 36`（`PAYLOAD=$(cat)` + `python3 - "$PAYLOAD" "$NOW"`）
- **问题**：
  1. 完整 hook payload（含 `prompt`、`tool_input`；`preToolUse` 对 Write 工具带**文件全文**）经 shell 变量后作为 **argv 参数**传给 python3。macOS `ARG_MAX` 约 1MB，`write_to_file` 大文件或超长 prompt 时 python3 启动失败（`Argument list too long`）→ 无 stdout JSON 响应 → 该事件丢失（Cursor 按 fail-open 不阻塞操作，但 Liang 收不到事件）。
  2. payload 全文会短暂出现在 `ps` 进程参数中，同机其他进程可见。
  3. 说明：脚本注释"不读取/不转发 prompt、代码、文件内容"不准确——实际是"读取并本地解析、但不转发"。数据始终留在本地、不外发。
- **修复方案**：payload 改走 stdin（同时删掉 `PAYLOAD=$(cat)`，否则 heredoc 与 stdin 冲突）：

```bash
python3 -c '
import json, sys, os
payload_json = sys.stdin.read()   # 直接从 stdin 读，不经过 argv
now = sys.argv[1]
try:
    raw = json.loads(payload_json)
except json.JSONDecodeError as e:
    print("{\"permission\":\"allow\",\"continue\":true}")
    sys.exit(0)
out = {
    "source": "cursor",
    "hook": raw.get("hook_event_name"),
    "timestamp": now,
    "conversation_id": raw.get("conversation_id"),
    "generation_id": raw.get("generation_id"),
    "tool_name": raw.get("tool_name"),
    "tool_use_id": raw.get("tool_use_id"),
    "subagent_id": raw.get("subagent_id"),
    "status": raw.get("status"),
    "failure_type": raw.get("failure_type"),
    "duration_ms": raw.get("duration") or raw.get("duration_ms")
}
with open(os.path.expanduser("~/.liang/cursor-events.jsonl"), "a") as f:
    f.write(json.dumps(out, ensure_ascii=False) + "\n")
print("{\"permission\":\"allow\",\"continue\":true}")
' "$NOW"
```

  验证方法：在 Cursor 中 `write_to_file` 写一个几百 KB 的文件，检查 `~/.liang/cursor-events.jsonl` 是否有对应事件、`~/.liang/bridge-error.log` 是否有记录。

### M7. 启动时即使 `cursorHooksEnabled=false`，adapter 仍会启动并标记已连接 ✅ 已修复

- **位置**：`Sources/Liang/StateEngine.swift:58, 80-94`
- **问题**：`start()` 无条件调用 `adapter.start()`（会创建 `~/.liang/cursor-events.jsonl` 并开始监听）；`cursorHooksEnabled` 订阅用 `dropFirst()`，启动时的关闭状态不会触发停止。运行时关闭 hooks 会进入 `.disconnected`，但**启动时就关闭**则始终 `.idle` 且 `isConnected=true`。
- **影响**：行为不一致，菜单栏/设置页状态显示错误。
- **修复方案**（原方案遗漏一处）：`start()` 中先判断 `settings.cursorHooksEnabled`，为 false 时不启动 adapter、`transition(to: .disconnected)`，**并跳过 `startHeartbeat()`**（`StateEngine.swift:60`）。否则 heartbeat 空转（`lastEventAt` 为 nil 时 `checkSessionIdle` 直接 return，虽无害但不干净）。

---

## 三、低优先级（Low）

| # | 位置 | 问题 |
|---|---|---|
| L1 | `GlowSettings.swift:309-346` + `AppDelegate.swift:73-92` | 两套"设备默认值"逻辑互相矛盾：工厂默认（刘海机全关）与 `applyDeviceDefaultsIfNeeded`（刘海机开刘海光晕）给出相反值；后者在 autosave 前执行从而覆盖前者，工厂逻辑实际是死代码。 |
| L2 | `StatusBarController.swift:181-186` | 菜单栏图标 **15fps 常驻重绘**（白色静态 idle 态每帧渲染同一张图），动画计时器从不停止，持续 CPU/电池开销。建议稳态时暂停。 |
| L3 | `CursorGlowController.swift:129-134`、`NotchExpansionController.swift:122-127` | 两个 30Hz 鼠标轮询在功能开启时始终运行（即使光标远离热区），可改为仅窗口可见/靠近热区时轮询。 |
| L4 | `StateEngine.swift:218-226` | waiting 超时复用了 `processingTimeout` 时长与文案，启用后 waiting 的保持时长与设置项名称不符。 |
| L5 | `OnboardingView.swift:485-496` | 卡片间切换悬停会先 `stopPreview()` 再 `startPreview()`，光晕窗口短暂隐藏 → 闪烁；建议直接切换 target 而不 stop。 |
| L6 | `SettingsView.swift:762`、`scripts/build-local-app.sh:16`、`scripts/Info.plist:20` | 版本号硬编码三处（0.1.3 / 0.1.3 / CFBundleVersion=4），易漂移，应从单一来源读取。 |
| L7 | `CursorSetupManager.swift:221-226` | `performInstall` 先删除旧桥接脚本再复制，复制失败会留下脚本缺失的中间态；建议原子替换（复制到临时文件再 rename）。 |
| L8 | `NotchExpansionController.swift:25-68` | 刘海展开面板只受 `notchExpansionEnabled` 控制，`glowEnabled=false` 时面板仍常驻显示任务列表（需确认是否为设计意图）。 |

---

## 四、Nit

- `Sources/Liang/OnboardingPreviewDriver.swift` — **整文件死代码**，全局无任何引用，连同 `start()/tick()` 循环可删除。
- `Color+Extensions.swift:27-35` — `NSColor(hex:)` 不校验 `scanHexInt64` 返回值，非法字符串静默得到黑色。
- `hooks/liang-bridge.sh` 与 `Sources/Liang/Resources/hooks/liang-bridge.sh` 是两份逐字节相同的副本，改一处忘另一处会漂移（建议构建时由单一源生成）。
- `StateEngine.swift:41` — `recentSignatures` 每次事件全量 filter，事件量大时有 O(n) 开销（n 通常很小，可忽略）。
- 项目**没有任何测试 target**（无 `Tests/` 目录），状态机/去重/任务合并等纯逻辑完全靠手测，建议为 StateEngine 补单元测试。
- `OnboardingWindowController.showThanksSheet` — thanks 窗口 `isReleasedWhenClosed=false` 且无持有者，每次完成引导泄漏一个窗口对象（单次安装仅一次，影响极小）。

---

## 五、重新审视补充（二次核对发现）

### S1（Low，已降级）success 被紧随 sessionEnd 覆盖 —— 影响极小，不建议修

- **位置**：`StateEngine.swift:159`（`handle` 里 `transition(to:)`）+ `:188`（`transition` 内 `invalidateTimers()`）+ `HookEvent.swift:77`（`sessionEnd → idle`）
- **问题**：若 `stop(status=completed)` 与 `sessionEnd` 紧邻到达，`stop` 转 `.success` 并启动 `successResetTimer`，紧接着 `sessionEnd` 转 `.idle`，`invalidateTimers()` 取消 success 计时器，success 实际显示远短于 `successMaxDuration`。
- **降级原因（前提修正）**：`stop` 是**每个 agent 回合**触发一次，`sessionEnd` 是**整个会话结束**才触发一次，两者通常间隔很久。正常使用中 `stop(completed)` 后 success 会完整走完 `successMaxDuration`（默认 20s），用户能正常看到绿色光晕。本问题仅在「agent 刚答完就立刻关闭会话」的边界瞬间发生，且此时用户本就在关会话，体感不可见。**Medium 评级过高，实际为 Low。**
- **为什么不建议修**：方案 (a)「success 期间忽略 sessionEnd」不会让 `successMaxDuration` 设置失效（反而让它更完整生效），但会**延迟 `sessionEnd → idle`**——会话关闭后光晕仍绿着 `successMaxDuration`（最长可达用户设置的 600s），把一个「几乎无感的罕见瞬间」换成「可能持续数分钟的明显错误」，得不偿失。
- **结论**：接受现状，不处理。

### S2（Low，新增）restart 重读会重放 30s 内事件

- **位置**：`CursorHookAdapter.swift:48-70`（`start()` 先 `events = []`，又 `readAvailableLines(filterStale: true)` 读回 30s 内事件）
- **问题**：`restart()`（文件缺失/截断/睡眠唤醒触发）时从头重读文件，`filterStale` 只保留 30s 内事件并重新 append；StateEngine 仅靠 1s 去重窗口兜底，**30s 内、1s 外的旧事件会被重新 handle → 状态重放**（如把已 success/idle 的任务重新置为 processing）。
- **与 H1 的耦合**：改为增量发布后此问题更明显——30s 内所有事件都会逐个重新进入状态机（当前 `events.last` 实现反而掩盖了它）。
- **修复**：`restart`/`start` 时跳过 `readAvailableLines`，直接把 `lastReadOffset` 设为文件末尾；或记录文件大小并在重启时从末尾续读。

---

## 六、建议修复顺序

1. **H1 + M1**（合一的增量发布，解决批量丢事件 + 无界增长）
2. **H2**（hooks.json 覆盖/删除，破坏用户既有配置）
3. **M5**（设置重启丢失，用户直接感知）
4. **M3 / M4**（并行会话与跨会话去重的状态错误）
5. **M2**（偶发事件永久丢失的竞态）
6. 其余（M6、M7、L 系列）按需处理
   （S1、S2 为低优先级，S1 不建议修，见第五节）

所有修复均不涉及架构改动，改动面小、风险低。
