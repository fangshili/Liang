#!/bin/bash
# Liang Claude Code Hook Bridge
# 行为：只读取 Claude Code 通过 stdin 发送的 Hook 元数据并本地解析，
# 归一化为统一事件格式写入 ~/.liang/claude-events.jsonl，不转发 prompt、代码、文件内容。
# stdout 保持静默（Claude Code 纯副作用 hook 不应输出任何内容，否则会被注入上下文或当作决策）。

LOG_DIR="$HOME/.liang"
mkdir -p "$LOG_DIR"
DEBUG_PATH="$LOG_DIR/bridge-debug.log"
ERROR_PATH="$LOG_DIR/bridge-error.log"
ENV_PATH="$LOG_DIR/bridge-env.log"

NOW=$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat())')

{
  echo ""
  echo "=== $NOW hook=$0 argv=$* ==="
  env | grep -Ei 'CLAUDE|HOOK|AGENT|ANTHROPIC' | sort
} >> "$ENV_PATH"

# payload 经 stdin 传入（不经过 argv，避免大 payload 触发 ARG_MAX 溢出）；由 Python 直接读取。
python3 -c '
import json, os, sys

payload = sys.stdin.read()
now = sys.argv[1]

EVENTS_PATH = os.path.expanduser("~/.liang/claude-events.jsonl")
DEBUG_PATH = os.path.expanduser("~/.liang/bridge-debug.log")
ERROR_PATH = os.path.expanduser("~/.liang/bridge-error.log")

with open(DEBUG_PATH, "a") as f:
    f.write("%s claude hook invoked, payload_bytes=%d\n" % (now, len(payload)))

if not payload or not payload.strip():
    with open(ERROR_PATH, "a") as f:
        f.write("%s stdin is empty\n" % now)
    sys.exit(0)

try:
    raw = json.loads(payload)
except json.JSONDecodeError as e:
    with open(ERROR_PATH, "a") as f:
        f.write("%s json decode error: %s\n" % (now, e))
    sys.exit(0)

event_name = raw.get("hook_event_name") or raw.get("event") or ""

# Claude Code 事件名（大驼峰）→ 统一事件名（小驼峰）。
EVENT_MAP = {
    "SessionStart": "sessionStart",
    "SessionEnd": "sessionEnd",
    "UserPromptSubmit": "beforeSubmitPrompt",
    "PreToolUse": "preToolUse",
    "PostToolUse": "postToolUse",
    "PostToolUseFailure": "postToolUseFailure",
    "SubagentStart": "subagentStart",
    "SubagentStop": "subagentStop",
    "Stop": "stop",
    "StopFailure": "stop",
}

hook = EVENT_MAP.get(event_name)
if not hook:
    with open(DEBUG_PATH, "a") as f:
        f.write("%s ignored event: %s\n" % (now, event_name))
    sys.exit(0)

# 成功/失败：Claude Code 用 Stop/StopFailure 两个事件区分，SubagentStop 用 is_error 布尔。
status = None
failure_type = None
if event_name == "SubagentStop":
    status = "error" if raw.get("is_error") else "completed"
elif event_name == "Stop":
    status = "completed"
elif event_name == "StopFailure":
    status = "error"
    failure_type = raw.get("error") or "stop_failure"

out = {
    "source": "claude_code",
    "hook": hook,
    "timestamp": now,
    "conversation_id": raw.get("session_id"),
    "generation_id": raw.get("prompt_id"),
    "tool_name": raw.get("tool_name"),
    "tool_use_id": raw.get("tool_use_id"),
    "subagent_id": raw.get("agent_id"),
    "status": status,
    "failure_type": failure_type,
}

with open(EVENTS_PATH, "a") as f:
    f.write(json.dumps(out, ensure_ascii=False) + "\n")

with open(DEBUG_PATH, "a") as f:
    f.write("%s wrote event: %s status=%s\n" % (now, hook, status))

sys.exit(0)
' "$NOW"

exit 0
