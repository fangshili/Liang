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

# 3. 写入 hooks.json
BRIDGE_PATH="$HOOKS_DIR/liang-bridge.sh"

cat > "$CONFIG_PATH" <<JSON
{
  "version": 1,
  "hooks": {
    "sessionStart": [{ "command": "$BRIDGE_PATH" }],
    "sessionEnd": [{ "command": "$BRIDGE_PATH" }],
    "beforeSubmitPrompt": [{ "command": "$BRIDGE_PATH" }],
    "preToolUse": [{ "command": "$BRIDGE_PATH" }],
    "postToolUse": [{ "command": "$BRIDGE_PATH" }],
    "postToolUseFailure": [{ "command": "$BRIDGE_PATH" }],
    "beforeShellExecution": [{ "command": "$BRIDGE_PATH" }],
    "afterShellExecution": [{ "command": "$BRIDGE_PATH" }],
    "beforeMCPExecution": [{ "command": "$BRIDGE_PATH" }],
    "afterMCPExecution": [{ "command": "$BRIDGE_PATH" }],
    "subagentStart": [{ "command": "$BRIDGE_PATH" }],
    "subagentStop": [{ "command": "$BRIDGE_PATH" }],
    "afterAgentThought": [{ "command": "$BRIDGE_PATH" }],
    "afterAgentResponse": [{ "command": "$BRIDGE_PATH" }],
    "stop": [{ "command": "$BRIDGE_PATH" }]
  }
}
JSON

echo "[Liang] 配置文件已写入 $CONFIG_PATH"
echo "[Liang] 安装完成。请完全退出并重新启动 Cursor 以使 Hook 生效。"
echo "[Liang] 你可以通过以下命令观察事件："
echo "        tail -f ~/.liang/cursor-events.jsonl"
