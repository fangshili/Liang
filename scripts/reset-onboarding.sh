#!/bin/bash
# reset-onboarding.sh
# 完全重置 Liang 到首次打开应用的状态，方便测试 onboarding 流程。
#
# 使用方法：
#   chmod +x scripts/reset-onboarding.sh
#   ./scripts/reset-onboarding.sh

set -euo pipefail

echo "=== Liang 完全重置脚本 ==="
echo ""

# 1. 删除所有 UserDefaults 数据
#    Bundle ID：打包后的 .app 使用 com.liang.app
#    swift run 直跑时可能以进程名 Liang 存储
echo "→ 清空 Liang 的 UserDefaults 数据..."
defaults delete com.liang.app 2>/dev/null || echo "  (com.liang.app 已为空)"
defaults delete Liang            2>/dev/null || echo "  (Liang 已为空)"

# 2. 删除事件文件
echo "→ 删除事件缓存文件..."
rm -f ~/.liang/cursor-events.jsonl 2>/dev/null || true
rm -f ~/.liang/claude-events.jsonl 2>/dev/null || true

# 3. 删除 Cursor hooks 配置
echo "→ 移除 Cursor hooks 配置..."
rm -f ~/.cursor/hooks.json           2>/dev/null || true
rm -f ~/.cursor/hooks/liang-bridge.sh 2>/dev/null || true

# 4. 移除 Claude Code hooks 配置（保留 settings.json 里的其他用户配置）
echo "→ 移除 Claude Code hooks 配置..."
rm -f ~/.claude/hooks/claude-bridge.sh 2>/dev/null || true
python3 - "$HOME/.claude/settings.json" "$HOME/.claude/hooks/claude-bridge.sh" <<'PY'
import json, os, sys

settings_path = sys.argv[1]
bridge_path = sys.argv[2]

if not os.path.exists(settings_path):
    sys.exit(0)

try:
    with open(settings_path) as f:
        config = json.load(f)
except (json.JSONDecodeError, OSError):
    sys.exit(0)

if not isinstance(config, dict):
    sys.exit(0)

hooks = config.get("hooks")
if isinstance(hooks, dict):
    for event, groups in list(hooks.items()):
        if not isinstance(groups, list):
            continue
        kept = []
        for group in groups:
            if not isinstance(group, dict):
                kept.append(group)
                continue
            handlers = group.get("hooks")
            if not isinstance(handlers, list):
                kept.append(group)
                continue
            new_handlers = [h for h in handlers if not (isinstance(h, dict) and h.get("command") == bridge_path)]
            if new_handlers:
                group["hooks"] = new_handlers
                kept.append(group)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if hooks:
        config["hooks"] = hooks
    else:
        config.pop("hooks", None)

with open(settings_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo ""
echo "✓ 重置完成！现在启动 Liang 将显示首次打开的 onboarding 流程。"
echo "  如需立即测试，请先退出 Liang 再重新打开。"
echo ""
echo "  状态检查："
echo "  → com.liang.app: $(defaults read com.liang.app 2>&1 || echo '已清空')"
echo "  → Liang:         $(defaults read Liang 2>&1 || echo '已清空')"
echo "  → ~/.liang/cursor-events.jsonl:  $([ -f ~/.liang/cursor-events.jsonl ] && echo '存在' || echo '不存在')"
echo "  → ~/.liang/claude-events.jsonl:  $([ -f ~/.liang/claude-events.jsonl ] && echo '存在' || echo '不存在')"
echo "  → ~/.cursor/hooks.json:          $([ -f ~/.cursor/hooks.json ] && echo '存在' || echo '不存在')"
echo "  → ~/.cursor/hooks/liang-bridge.sh: $([ -f ~/.cursor/hooks/liang-bridge.sh ] && echo '存在' || echo '不存在')"
echo "  → ~/.claude/hooks/claude-bridge.sh: $([ -f ~/.claude/hooks/claude-bridge.sh ] && echo '存在' || echo '不存在')"
