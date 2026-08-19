#!/bin/bash
# Liang Cursor Hook 卸载脚本

set -e

HOOKS_DIR="$HOME/.cursor/hooks"
CONFIG_PATH="$HOME/.cursor/hooks.json"

echo "[Liang] 卸载 Cursor Hook..."

# 1. 删除桥接脚本
rm -f "$HOOKS_DIR/liang-bridge.sh"

# 2. 从 hooks.json 移除指向 liang-bridge.sh 的条目（保留其他工具的配置）
python3 - "$CONFIG_PATH" "$HOOKS_DIR/liang-bridge.sh" <<'PY'
import json
import os
import sys

config_path = sys.argv[1]
bridge_path = sys.argv[2]

if not os.path.exists(config_path):
    print("no config file")
    sys.exit(0)

try:
    with open(config_path) as f:
        config = json.load(f)
except (json.JSONDecodeError, OSError):
    os.remove(config_path)
    print("removed config (invalid)")
    sys.exit(0)

if not isinstance(config, dict):
    os.remove(config_path)
    print("removed config (not a dict)")
    sys.exit(0)

hooks = config.get("hooks")
if not isinstance(hooks, dict):
    os.remove(config_path)
    print("removed config (no hooks)")
    sys.exit(0)

for event, commands in list(hooks.items()):
    if not isinstance(commands, list):
        continue
    kept = [c for c in commands if not (isinstance(c, dict) and c.get("command") == bridge_path)]
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]

if not hooks:
    os.remove(config_path)
    print("removed config (hooks empty)")
else:
    config["hooks"] = hooks
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("updated config")
PY

echo "[Liang] 已移除 liang-bridge.sh 及 hooks.json 中的 Liang 条目"
echo "[Liang] 请完全退出并重新启动 Cursor 以停止调用 Hook。"
