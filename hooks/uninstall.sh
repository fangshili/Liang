#!/bin/bash
# Liang Cursor Hook 卸载脚本

set -e

HOOKS_DIR="$HOME/.cursor/hooks"
CONFIG_PATH="$HOME/.cursor/hooks.json"

echo "[Liang] 卸载 Cursor Hook..."

rm -f "$HOOKS_DIR/liang-bridge.sh"
rm -f "$CONFIG_PATH"

echo "[Liang] 已移除 $CONFIG_PATH 和 $HOOKS_DIR/liang-bridge.sh"
echo "[Liang] 请完全退出并重新启动 Cursor 以停止调用 Hook。"
