#!/bin/bash
# Liang Cursor Hook Bridge
# 安装：放到项目或用户目录，chmod +x，并在 ~/.cursor/hooks.json 中引用。
# 行为：只读取 Cursor 通过 stdin 发送的 Hook 元数据并本地解析，不转发 prompt、代码、文件内容。

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

# payload 经 stdin 传入（不经过 argv，避免 ARG_MAX 溢出与 ps 可见）；由 Python 直接读取。
python3 -c '
import json
import os
import sys

payload_json = sys.stdin.read()
now = sys.argv[1]

LOG_DIR = os.path.expanduser("~/.liang")
EVENTS_PATH = os.path.join(LOG_DIR, "cursor-events.jsonl")
DEBUG_PATH = os.path.join(LOG_DIR, "bridge-debug.log")
ERROR_PATH = os.path.join(LOG_DIR, "bridge-error.log")

with open(DEBUG_PATH, "a") as f:
    f.write("%s hook invoked, payload_bytes=%d, cwd=%s\n" % (now, len(payload_json), os.getcwd()))

# 必须向 stdout 输出 JSON 响应，否则 Cursor 可能认为 Hook 失败或重复调用。
if not payload_json or not payload_json.strip():
    with open(ERROR_PATH, "a") as f:
        f.write("%s stdin is empty\n" % now)
    print("{\"permission\":\"allow\",\"continue\":true}")
    sys.exit(0)

try:
    raw = json.loads(payload_json)
except json.JSONDecodeError as e:
    with open(ERROR_PATH, "a") as f:
        f.write("%s json decode error: %s, payload=%r\n" % (now, e, payload_json[:500]))
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

with open(EVENTS_PATH, "a") as f:
    f.write(json.dumps(out, ensure_ascii=False) + "\n")

with open(DEBUG_PATH, "a") as f:
    f.write("%s wrote event: %s\n" % (now, out["hook"]))

print("{\"permission\":\"allow\",\"continue\":true}")
' "$NOW"

exit 0
