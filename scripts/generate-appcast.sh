#!/bin/bash
set -e

# Liang appcast.xml 生成脚本
# 用法：
#   ./scripts/generate-appcast.sh /path/to/updates
#
# 说明：
#   将各个版本的 .dmg 更新包（建议命名为 Liang-0.1.1.dmg 等）放在目录中，
#   脚本会调用 Sparkle 的 generate_appcast 生成 appcast.xml。
#   上传 appcast.xml 到 GitHub Pages（https://fangshili.github.io/Liang/appcast.xml），
#   更新包本身上传到对应 GitHub Release 的 Assets。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

UPDATE_DIR="${1:-$PROJECT_DIR/build/updates}"
DOWNLOAD_PREFIX="${LIANG_DOWNLOAD_PREFIX:-https://github.com/fangshili/Liang/releases/download}"
FEED_URL="${LIANG_FEED_URL:-https://fangshili.github.io/Liang/appcast.xml}"

if [ ! -d "$UPDATE_DIR" ]; then
    echo "[Liang] 错误：更新包目录不存在：$UPDATE_DIR"
    echo "[Liang] 请把每个版本的 .dmg 放在该目录后再运行。"
    exit 1
fi

# 查找 Sparkle 的 generate_appcast 工具
GENERATE_APPCAST="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [ ! -f "$GENERATE_APPCAST" ]; then
    echo "[Liang] 未找到 Sparkle 的 generate_appcast：$GENERATE_APPCAST"
    echo "[Liang] 请先运行一次 swift build -c release 以下载 Sparkle 依赖，"
    echo "        或从 https://github.com/sparkle-project/Sparkle/releases 下载 Sparkle 工具包。"
    exit 1
fi

chmod +x "$GENERATE_APPCAST"

echo "[Liang] 扫描更新包目录：$UPDATE_DIR"
echo "[Liang] 下载地址前缀：$DOWNLOAD_PREFIX"

cd "$UPDATE_DIR"
"$GENERATE_APPCAST" \
    --download-url-prefix "$DOWNLOAD_PREFIX/" \
    --full-release-notes-url "$FEED_URL" \
    .

echo "[Liang] appcast.xml 已生成：$UPDATE_DIR/appcast.xml"
echo "[Liang] 请检查 enclosure url 是否指向正确的 GitHub Release 下载地址。"
echo "[Liang] 上传步骤："
echo "  1. 将 $UPDATE_DIR/appcast.xml 提交/推送到 gh-pages 分支（路径 /appcast.xml）。"
echo "  2. 将 .dmg 文件上传到对应 GitHub Release 的 Assets。"
