#!/bin/bash
# Liang 本地测试 .app 构建脚本
# 用法：./scripts/build-local-app.sh
# 产物：build/Liang.app（不公证、不创建 DMG，仅用于本地功能测试）
# 说明：Xcode / swift run 启动的是裸可执行文件，没有 Info.plist 和 Sparkle.framework，
#      会导致 Sparkle 更新检查失败、菜单项禁用等问题。本脚本组装一个完整的 .app bundle，
#      用于测试需要完整 bundle 的功能（Sparkle、资源 bundle、图标等）。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Liang"
BUNDLE_ID="com.liang.app"
VERSION="0.1.11"
ICON_SOURCE="$PROJECT_DIR/assets/icon-l-glow.png"

# 默认 Debug 构建；可通过 ./scripts/build-local-app.sh release 改为 Release
CONFIG="${1:-debug}"
case "$CONFIG" in
    release|Release)
        CONFIG="release"
        BUILD_PRODUCTS_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/release"
        ;;
    *)
        CONFIG="debug"
        BUILD_PRODUCTS_DIR="$PROJECT_DIR/.build/debug"
        ;;
esac

echo "[Liang] 开始 $CONFIG 构建..."
cd "$PROJECT_DIR"
swift build -c "$CONFIG"

echo "[Liang] 清理旧产物..."
rm -rf "$BUILD_DIR/$APP_NAME.app"
mkdir -p "$BUILD_DIR"

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXEC_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$EXEC_DIR"
mkdir -p "$RES_DIR/hooks"
mkdir -p "$FRAMEWORKS_DIR"

echo "[Liang] 生成 AppIcon.icns..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png"       >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png"    >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png"       >/dev/null
sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png"    >/dev/null
sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png"     >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png"  >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png"     >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png"  >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png"     >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png"  >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns"
find "$ICONSET_DIR" -type f -delete
find "$ICONSET_DIR" -type d -delete

echo "[Liang] 组装 .app bundle..."
cp "$BUILD_PRODUCTS_DIR/$APP_NAME" "$EXEC_DIR/$APP_NAME"
chmod +x "$EXEC_DIR/$APP_NAME"

# SPM 不会为可执行目标自动添加 @executable_path/../Frameworks，手动添加以便运行时找到嵌入的框架
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXEC_DIR/$APP_NAME" || true

cp "$PROJECT_DIR/scripts/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$RES_DIR/AppIcon.icns"
cp "$PROJECT_DIR/Sources/Liang/Resources/hooks/liang-bridge.sh" "$RES_DIR/hooks/liang-bridge.sh"
chmod +x "$RES_DIR/hooks/liang-bridge.sh"

# SPM 资源 bundle，Bundle.module 运行时需要
if [ -d "$BUILD_PRODUCTS_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BUILD_PRODUCTS_DIR/${APP_NAME}_${APP_NAME}.bundle" "$RES_DIR/"
fi

echo "[Liang] 替换 Info.plist 中的版本号..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"

echo "[Liang] 嵌入 Sparkle.framework..."
SPARKLE_XCFRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework"
if [ -d "$SPARKLE_XCFRAMEWORK" ]; then
    SPARKLE_FW=$(find "$SPARKLE_XCFRAMEWORK" -maxdepth 2 -name "Sparkle.framework" -type d | head -1)
    if [ -n "$SPARKLE_FW" ]; then
        cp -R "$SPARKLE_FW" "$FRAMEWORKS_DIR/"
        echo "[Liang] 已复制 Sparkle.framework"
    else
        echo "[Liang] 警告：未在 Sparkle.xcframework 中找到 Sparkle.framework"
    fi
else
    echo "[Liang] 警告：未找到 Sparkle.xcframework，请确认 swift build 已下载依赖"
fi

echo "[Liang] 对 .app 进行 ad-hoc 签名..."
codesign --sign - --force --deep "$APP_BUNDLE"

echo "[Liang] 验证签名..."
codesign --verify --verbose "$APP_BUNDLE" || true

echo "[Liang] 本地 .app 已生成：$APP_BUNDLE"
echo "[Liang] 运行测试：open \"$APP_BUNDLE\""
echo "[Liang] 提示：这是本地测试包，未经过 Developer ID 签名和公证，仅用于功能验证。"
