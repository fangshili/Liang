# Cursor Hooks 集成方案

> 本文件持久化 Liang 与 Cursor 的集成方法，避免会话间丢失。

## 1. 关键事实

- Cursor Hooks 通过 `~/.cursor/hooks.json`（用户级）或项目级 `.cursor/hooks.json` 配置。
- Cursor 以 **stdio JSON** 调用外部脚本，没有现成的本地事件目录。
- 桥接脚本自行写文件，Liang 通过只读监听该文件获得事件。
- 可用事件：`sessionStart/End`、`beforeSubmitPrompt`、`pre/postToolUse`、`postToolUseFailure`、`before/afterShellExecution`、`before/afterMCPExecution`、`subagentStart/Stop`、`afterAgentThought`、`afterAgentResponse`、`stop`。

## 2. 推荐配置

### 2.1 `~/.cursor/hooks.json`

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [{ "command": "./hooks/liang-bridge.sh" }],
    "sessionEnd":   [{ "command": "./hooks/liang-bridge.sh" }],
    "beforeSubmitPrompt": [{ "command": "./hooks/liang-bridge.sh" }],
    "preToolUse": [{ "command": "./hooks/liang-bridge.sh" }],
    "postToolUse": [{ "command": "./hooks/liang-bridge.sh" }],
    "postToolUseFailure": [{ "command": "./hooks/liang-bridge.sh" }],
    "beforeShellExecution": [{ "command": "./hooks/liang-bridge.sh" }],
    "afterShellExecution": [{ "command": "./hooks/liang-bridge.sh" }],
    "beforeMCPExecution": [{ "command": "./hooks/liang-bridge.sh" }],
    "afterMCPExecution": [{ "command": "./hooks/liang-bridge.sh" }],
    "subagentStart": [{ "command": "./hooks/liang-bridge.sh" }],
    "subagentStop": [{ "command": "./hooks/liang-bridge.sh" }],
    "afterAgentThought": [{ "command": "./hooks/liang-bridge.sh" }],
    "afterAgentResponse": [{ "command": "./hooks/liang-bridge.sh" }],
    "stop": [{ "command": "./hooks/liang-bridge.sh" }]
  }
}
```

### 2.2 桥接脚本 `hooks/liang-bridge.sh`

```bash
#!/bin/bash
# Liang Cursor Hook Bridge
# 安装：放到项目或用户目录，chmod +x，并在 ~/.cursor/hooks.json 中引用。
# 行为：只读取 Cursor 通过 stdin 发送的 Hook 元数据，不读取/不转发 prompt、代码、文件内容。

LOG_DIR="$HOME/.liang"
mkdir -p "$LOG_DIR"
EVENTS_PATH="$LOG_DIR/cursor-events.jsonl"
DEBUG_PATH="$LOG_DIR/bridge-debug.log"
ERROR_PATH="$LOG_DIR/bridge-error.log"
ENV_PATH="$LOG_DIR/bridge-env.log"

NOW=$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat())')

# 记录环境变量，便于排查 Cursor 如何传递上下文。
{
  echo ""
  echo "=== $NOW hook=$0 argv=$* ==="
  env | grep -Ei 'CURSOR|HOOK|AGENT|VSCODE|SSH' | sort
} >> "$ENV_PATH"

# 读取 stdin 内容。
PAYLOAD=$(cat)
PAYLOAD_LEN=${#PAYLOAD}

echo "$NOW hook invoked, payload_bytes=$PAYLOAD_LEN, argv=$*, cwd=$(pwd)" >> "$DEBUG_PATH"

# 必须向 stdout 输出 JSON 响应，否则 Cursor 可能认为 Hook 失败或重复调用。
if [ -z "$PAYLOAD" ] || [ "$PAYLOAD" = " " ]; then
  echo "$NOW stdin is empty" >> "$ERROR_PATH"
  echo '{"permission":"allow","continue":true}'
  exit 0
fi

# 尝试用 Python 提取安全元数据并追加到事件文件。
python3 - "$PAYLOAD" "$NOW" <<'PY'
import json
import sys
import os

payload_json = sys.argv[1]
now = sys.argv[2]

LOG_DIR = os.path.expanduser("~/.liang")
EVENTS_PATH = os.path.join(LOG_DIR, "cursor-events.jsonl")
DEBUG_PATH = os.path.join(LOG_DIR, "bridge-debug.log")
ERROR_PATH = os.path.join(LOG_DIR, "bridge-error.log")

try:
    raw = json.loads(payload_json)
except json.JSONDecodeError as e:
    with open(ERROR_PATH, "a") as f:
        f.write(f"{now} json decode error: {e}, payload={payload_json[:500]!r}\n")
    print('{"permission":"allow","continue":true}')
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

with open(EVENTS_PATH, "a") as f:
    f.write(json.dumps(out, ensure_ascii=False) + "\n")

with open(DEBUG_PATH, "a") as f:
    f.write(f"{now} wrote event: {out['hook']}\n")

print('{"permission":"allow","continue":true}')
PY

exit 0
```

- 脚本只提取安全元数据，**不读取、不转发 prompt、代码、文件内容**。
- 输出追加到 `~/.liang/cursor-events.jsonl`。
- 必须向 stdout 输出 JSON 响应 `{"permission":"allow","continue":true}`，否则 Cursor 可能认为 Hook 失败或重复调用。

## 3. Liang 监听方式

- 使用 `DispatchSource` 监听 `~/.liang/cursor-events.jsonl` 文件变化。
- 解析新增行，转换为统一事件模型 `HookEvent`。
- 文件不存在或解析失败时发出 `disconnected`/`unknown` 状态，不静默忽略。

## 4. 状态映射草案（V1）

| 状态 | 触发事件 | 恢复条件 |
|---|---|---|
| `processing` | `sessionStart`、`beforeSubmitPrompt`、`preToolUse`、`subagentStart`、`afterAgentThought`、`postToolUse`、`postToolUseFailure`、`afterShellExecution`、`afterMCPExecution` | 收到成功/错误/超时 |
| `success` | `stop(status=completed)`、`subagentStop(status=completed)` | 保持 3s 后转 `idle` |
| `error` | `stop(status=error/aborted)`、`postToolUseFailure`、`subagentStop(status=error/aborted)` | 保持到下一次事件或用户手动清除 |
| `idle` | `sessionEnd` 或 60s 无事件 | - |
| `waiting` | `afterAgentResponse`（AI 回复后等待用户输入）、`beforeShellExecution`、`beforeMCPExecution` | 用户确认/发送新消息或超时 |

## 5. 部署步骤

项目已提供安装脚本，位于 `hooks/install.sh`。

```bash
cd /Users/fangshili/CodeBuddy/liang
chmod +x hooks/install.sh
./hooks/install.sh
```

脚本会完成：
1. 创建 `~/.cursor/hooks/` 目录。
2. 复制 `liang-bridge.sh` 到 `~/.cursor/hooks/` 并设置可执行权限。
3. 创建 `~/.cursor/hooks.json`，将所有可用 Hook 指向该桥接脚本。

**必须完全退出并重新启动 Cursor**，Hook 才会生效。

验证是否生效：

```bash
tail -f ~/.liang/cursor-events.jsonl
```

然后在 Cursor 中发送一条消息或执行一个操作，观察该文件是否有新事件写入。

如需卸载：

```bash
./hooks/uninstall.sh
```

## 6. 关键注意事项（已踩坑）

1. **桥接脚本必须输出 JSON 响应**：
   - Cursor Hooks 是双向通信。如果脚本不向 stdout 输出响应，Cursor 可能认为调用失败或行为异常（例如重复调用、stdin 为空）。
   - 当前响应为 `{"permission":"allow","continue":true}`，表示允许操作继续。

2. **`~/.cursor/hooks.json` 中 command 建议使用绝对路径**：
   - Cursor 执行 command 时不一定经过 shell，`~` 可能不会被展开。
   - `install.sh` 会自动写入绝对路径 `/Users/<user>/.cursor/hooks/liang-bridge.sh`。

3. **Hook 修改后必须完全重启 Cursor**：
   - 仅关闭窗口不够，需要 Cmd+Q 完全退出后重新打开。

4. **排查日志位置**：
   - `~/.liang/cursor-events.jsonl`：成功解析后的事件。
   - `~/.liang/bridge-debug.log`：每次 Hook 调用和写入事件记录。
   - `~/.liang/bridge-error.log`：stdin 为空或 JSON 解析失败的记录。
   - `~/.liang/bridge-env.log`：Hook 调用时的相关环境变量。

## 7. 不确定/待确认项

1. **等待确认**：当前采用 `afterAgentResponse` 推断“AI 回复后等你输入下一条”。如需要真正的弹窗确认（shell/MCP），Hooks 无法直接观测，需用超时启发式。
2. **Hook 配置位置**：默认用户级 `~/.cursor/hooks.json`，项目级配置按同样结构。
3. **桥接脚本部署**：需要 `chmod +x`，依赖 macOS 自带 Python 3。
4. **真实事件字段**：Cursor 官方文档中的字段名可能与桥接脚本假设的 `hook_event_name`、`conversation_id` 等存在差异，需要通过真实运行验证并调整。

## 7. 隐私声明

- Bridge 只提取安全元数据，不读取、不转发 prompt、代码、文件内容。
- Liang 只读取本地事件文件的元数据字段。
