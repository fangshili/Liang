#!/bin/bash
set -e

# Liang DMG 打包脚本
# 用法：./scripts/build-dmg.sh
# 产物：build/Liang.dmg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Liang"
BUNDLE_ID="com.liang.app"
VERSION="0.1.7"
# Sparkle 使用 CFBundleVersion 判断是否有新版本，每次发布必须递增。
BUILD_NUMBER="8"
ICON_SOURCE="$PROJECT_DIR/assets/icon-l-glow.png"

# 签名与公证配置
# 1) 留空则自动查找 keychain 中的 "Developer ID Application" 证书
DEVELOPER_ID="${LIANG_DEVELOPER_ID:-}"
# 2) notarytool keychain profile 名称，留空则跳过公证
NOTARY_PROFILE="${LIANG_NOTARY_PROFILE:-}"

echo "[Liang] 开始 Release 构建..."
cd "$PROJECT_DIR"
swift build -c release

echo "[Liang] 清理旧产物..."
rm -f "$BUILD_DIR/$APP_NAME.dmg"
mkdir -p "$BUILD_DIR"

# 在临时目录中组装 .app，避免复用 build/Liang.app 时受 macOS 扩展属性
#（如 com.apple.provenance）限制而导致文件修改/创建失败。
STAGING_DIR=$(mktemp -d /tmp/liang-build-XXXXXX)
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"

# 脚本结束时把最终 .app 复制到 build/ 目录，以便本地测试；然后清理临时目录。
# build/Liang.app 可能带有系统保护的 com.apple.provenance 扩展属性，直接删除会触发
# IDE 批量删除安全确认，因此先 mv 到 .old 后缀再由用户/系统择机清理。
cleanup() {
    echo "[Liang] 复制 .app 到 build/ 目录..."
    if [ -d "$BUILD_DIR/$APP_NAME.app" ]; then
        rm -rf "$BUILD_DIR/$APP_NAME.app.old"
        mv "$BUILD_DIR/$APP_NAME.app" "$BUILD_DIR/$APP_NAME.app.old"
    fi
    cp -R "$APP_BUNDLE" "$BUILD_DIR/$APP_NAME.app"
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "[Liang] 生成 AppIcon.icns..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
# 复用目录，避免 rm -rf iconset 触发安全确认
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
EXEC_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"
mkdir -p "$EXEC_DIR"
mkdir -p "$RES_DIR/hooks"

cp "$PROJECT_DIR/.build/arm64-apple-macosx/release/Liang" "$EXEC_DIR/Liang"
chmod +x "$EXEC_DIR/Liang"
# SPM 不会为可执行目标自动添加 @executable_path/../Frameworks，
# 手动添加以便运行时找到嵌入的 Sparkle.framework。
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXEC_DIR/Liang" || true
cp "$PROJECT_DIR/scripts/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$RES_DIR/AppIcon.icns"
cp "$PROJECT_DIR/Sources/Liang/Resources/hooks/liang-bridge.sh" "$RES_DIR/hooks/liang-bridge.sh"
chmod +x "$RES_DIR/hooks/liang-bridge.sh"
# SPM 资源 bundle，Bundle.module 运行时需要
if [ -d "$PROJECT_DIR/.build/arm64-apple-macosx/release/Liang_Liang.bundle" ]; then
    cp -R "$PROJECT_DIR/.build/arm64-apple-macosx/release/Liang_Liang.bundle" "$RES_DIR/Liang_Liang.bundle"
fi

echo "[Liang] 替换 Info.plist 中的版本号..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"

echo "[Liang] 嵌入 Sparkle.framework..."
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

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

echo "[Liang] 对 .app 进行签名..."
if [ -z "$DEVELOPER_ID" ]; then
    DEVELOPER_ID=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
fi

if [ -n "$DEVELOPER_ID" ]; then
    echo "[Liang] 使用证书: $DEVELOPER_ID"
    # Sparkle.framework 内部包含 Updater.app、Autoupdate 和 XPCServices，
    # 需要用 --deep 递归签名，否则公证会报子组件无有效签名/无时间戳。
    if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
        codesign --sign "$DEVELOPER_ID" --force --deep --options runtime --timestamp "$FRAMEWORKS_DIR/Sparkle.framework"
    fi
    codesign --sign "$DEVELOPER_ID" --force --options runtime --timestamp "$APP_BUNDLE"
else
    echo "[Liang] 未找到 Developer ID Application 证书，回退到 ad-hoc 签名..."
    codesign --sign - --force --options runtime "$APP_BUNDLE" 2>/dev/null || codesign --sign - --force "$APP_BUNDLE"
fi

echo "[Liang] 验证签名..."
codesign --verify --verbose "$APP_BUNDLE" || true

echo "[Liang] 生成 DMG 背景图..."
python3 "$SCRIPT_DIR/generate-dmg-background.py"

echo "[Liang] 创建 DMG..."
TMP_DMG="$BUILD_DIR/Liang-tmp.dmg"
rm -f "$TMP_DMG"

# 估算大小并创建可读写临时 DMG
APP_SIZE_MB=$(du -sm "$APP_BUNDLE" | cut -f1)
DMG_SIZE_MB=$((APP_SIZE_MB + 30))
hdiutil create -size "${DMG_SIZE_MB}m" -volname "$APP_NAME" -fs HFS+ -type UDIF -o "$TMP_DMG" >/dev/null

# 清理可能残留的同名挂载
for vol in "/Volumes/$APP_NAME" "/Volumes/$APP_NAME 1" "/Volumes/$APP_NAME 2" "/Volumes/$APP_NAME 3"; do
    if mount | grep -q "$vol"; then
        hdiutil detach "$vol" -force >/dev/null 2>&1 || true
    fi
done

# 挂载并获取实际挂载路径
MOUNT_POINT=$(hdiutil attach "$TMP_DMG" -nobrowse -noverify -noautoopen | grep -o '/Volumes/.*' | tail -1)
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo "[Liang] 挂载 DMG 失败"
    exit 1
fi
sleep 2

# 复制 app、创建 Applications 别名、设置背景图和卷图标
cp -R "$APP_BUNDLE" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"
mkdir -p "$MOUNT_POINT/.background"
cp "$BUILD_DIR/dmg-background.png" "$MOUNT_POINT/.background/background.png"
cp "$BUILD_DIR/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
bless --folder "$MOUNT_POINT" --openfolder "$MOUNT_POINT" 2>/dev/null || true

# 设置 Finder 窗口布局
osascript <<EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 860, 600}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set text size of viewOptions to 12
        set background picture of viewOptions to POSIX file "$MOUNT_POINT/.background/background.png"
        set position of item "$APP_NAME.app" of container window to {150, 140}
        set position of item "Applications" of container window to {510, 140}
        close
    end tell
end tell
EOF

# 卸载并压缩
hdiutil detach "$MOUNT_POINT" -force >/dev/null
hdiutil convert "$TMP_DMG" -format UDZO -o "$BUILD_DIR/$APP_NAME.dmg" >/dev/null
find "$BUILD_DIR" -maxdepth 1 -name 'Liang-tmp.dmg' -type f -delete

# 为 DMG 文件本身设置应用图标
echo "[Liang] 设置 DMG 文件图标..."
clang -framework Cocoa "$SCRIPT_DIR/seticon.m" -o "$BUILD_DIR/seticon" 2>/dev/null || true
"$BUILD_DIR/seticon" "$APP_BUNDLE" "$BUILD_DIR/$APP_NAME.dmg" || true

# 公证与 stapling
if [ -n "$NOTARY_PROFILE" ]; then
    echo "[Liang] 提交 DMG 公证（profile: $NOTARY_PROFILE）..."
    xcrun notarytool submit "$BUILD_DIR/$APP_NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "[Liang] Staple 公证 ticket..."
    xcrun stapler staple "$BUILD_DIR/$APP_NAME.dmg"
    echo "[Liang] 验证 staple..."
    xcrun stapler validate "$BUILD_DIR/$APP_NAME.dmg" || true
else
    echo "[Liang] 未配置 LIANG_NOTARY_PROFILE，跳过公证。"
    echo "[Liang] 要启用公证，请先运行："
    echo "      xcrun notarytool store-credentials 'liang-notary' --apple-id your@email.com --team-id TEAM_ID --password app-specific-password"
    echo "      然后执行：LIANG_NOTARY_PROFILE='liang-notary' ./scripts/build-dmg.sh"
fi

echo "[Liang] 打包完成：$BUILD_DIR/$APP_NAME.dmg"
