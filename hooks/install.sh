#!/bin/bash
# Liang Cursor Hook 安装脚本
# 作用：将桥接脚本部署到 ~/.cursor/hooks/ 并配置 ~/.cursor/hooks.json
# 注意：需要重启 Cursor 才能生效。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.cursor/hooks"
CONFIG_PATH="$HOME/.cursor/hooks.json"

echo "[Liang] 安装 Cursor Hook..."

# 1. 确保目标目录存在
mkdir -p "$HOOKS_DIR"

# 2. 复制桥接脚本
cp "$SCRIPT_DIR/liang-bridge.sh" "$HOOKS_DIR/liang-bridge.sh"
chmod +x "$HOOKS_DIR/liang-bridge.sh"
echo "[Liang] 桥接脚本已复制到 $HOOKS_DIR/liang-bridge.sh"

# 3. 合并写入 hooks.json（保留已有配置，仅按事件名插入/更新 Liang 条目）
BRIDGE_PATH="$HOOKS_DIR/liang-bridge.sh"

python3 - "$CONFIG_PATH" "$BRIDGE_PATH" <<'PY'
import json
import os
import sys

config_path = sys.argv[1]
bridge_path = sys.argv[2]

events = [
    "sessionStart", "sessionEnd", "beforeSubmitPrompt", "preToolUse",
    "postToolUse", "postToolUseFailure", "beforeShellExecution",
    "afterShellExecution", "beforeMCPExecution", "afterMCPExecution",
    "subagentStart", "subagentStop", "afterAgentThought",
    "afterAgentResponse", "stop"
]

config = {}
if os.path.exists(config_path):
    try:
        with open(config_path) as f:
            config = json.load(f)
    except (json.JSONDecodeError, OSError):
        config = {}
if not isinstance(config, dict):
    config = {}

hooks = config.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

for event in events:
    commands = hooks.get(event)
    if not isinstance(commands, list):
        commands = []
    commands = [c for c in commands if not (isinstance(c, dict) and c.get("command") == bridge_path)]
    commands.append({"command": bridge_path})
    hooks[event] = commands

config["hooks"] = hooks
config.setdefault("version", 1)

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo "[Liang] 配置文件已合并写入 $CONFIG_PATH"
echo "[Liang] 安装完成。请完全退出并重新启动 Cursor 以使 Hook 生效。"
echo "[Liang] 你可以通过以下命令观察事件："
echo "        tail -f ~/.liang/cursor-events.jsonl"
