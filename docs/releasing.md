# Liang 发布流程

## 前置条件

- Apple Developer 账号已通过审核。
- 已创建 `Developer ID Application` 证书。
- 已配置 notarytool keychain profile（例如 `liang-notary`）。
- 已注册 bundle ID：`com.liang.app`。
- GitHub 仓库：`https://github.com/fangshili/Liang`
- Appcast feed URL：`https://fangshili.github.io/Liang/appcast.xml`

## 每次发布新版本的步骤

### 1. 更新版本号

编辑以下文件中的版本号：

- `scripts/build-dmg.sh`：修改 `VERSION`。
- `scripts/Info.plist`：修改 `CFBundleShortVersionString`（打包脚本会覆盖，但保持同步更稳妥）。

示例：从 `0.1.0` 改为 `0.1.1`。

### 2. 构建并打包

```bash
LIANG_NOTARY_PROFILE="liang-notary" ./scripts/build-dmg.sh
```

产物：
- `build/Liang.app`
- `build/Liang.dmg`（已签名、已公证、已 staple）

### 3. 创建 GitHub Release

1. 在 GitHub 仓库页面点击 **Releases → Draft a new release**。
2. 创建新标签，例如 `v0.1.1`。
3. Release title 填写版本号，例如 `Liang 0.1.1`。
4. 填写 release notes。
5. 上传 `build/Liang.dmg` 到 Release Assets。

建议将上传的 .dmg 重命名为带版本号的文件名，例如 `Liang-0.1.1.dmg`，这样 appcast.xml 中的下载链接更清晰。

### 4. 生成并上传 appcast.xml

准备一个目录，放入当前及历史版本的 .dmg 文件（例如 `build/updates/`）：

```bash
mkdir -p build/updates
cp build/Liang-0.1.0.dmg build/updates/
cp build/Liang-0.1.1.dmg build/updates/
```

生成 appcast.xml：

```bash
LIANG_DOWNLOAD_PREFIX="https://github.com/fangshili/Liang/releases/download" \
  ./scripts/generate-appcast.sh build/updates
```

> 注意：`LIANG_DOWNLOAD_PREFIX` 只需要前缀路径，generate_appcast 会自动拼接版本目录。实际 URL 示例：
> `https://github.com/fangshili/Liang/releases/download/v0.1.1/Liang-0.1.1.dmg`

检查生成的 `build/updates/appcast.xml` 中的 `<enclosure url="..." />` 是否指向正确的 GitHub Release 下载地址。

### 5. 部署 appcast.xml 到 GitHub Pages

将 `appcast.xml` 放到 GitHub Pages 服务的仓库根目录，最终访问地址为：

```
https://fangshili.github.io/Liang/appcast.xml
```

建议为 `gh-pages` 分支或 GitHub Actions 自动部署。

### 6. 验证更新链路

1. 在本地安装旧版本 DMG（例如 `v0.1.0`）。
2. 确保 `~/Library/Logs/Liang` 中没有 Sparkle 相关错误。
3. 点击菜单栏「检查更新…」，应能检测到 `v0.1.1` 并提示下载安装。

## 本地测试完整 .app（不公证）

`swift run` 或 Xcode ▶ Run 启动的是裸可执行文件，缺少 `Info.plist` 和嵌入的 `Sparkle.framework`，会导致 Sparkle 报错、菜单栏「检查更新…」禁用。要测试完整功能，请使用本地构建脚本：

```bash
./scripts/build-local-app.sh
```

产物：`build/Liang.app`（ad-hoc 签名，未公证，仅用于本地测试）。

运行：

```bash
open build/Liang.app
```

该脚本支持 Release 构建：

```bash
./scripts/build-local-app.sh release
```

## 首次发布（v0.1.0）的特别说明

首次发布时，appcast.xml 可以只包含 `v0.1.0` 一个 item。Sparkle 默认只在应用启动后自动检查更新，因此首次安装的用户不会立即收到更新提示，这符合预期。

## 常见问题

### Sparkle 找不到 generate_appcast

确保已经运行过一次 `swift build -c release`，这样 SPM 会下载 Sparkle 到 `.build/checkouts/Sparkle`。`scripts/generate-appcast.sh` 会从该位置调用 `bin/generate_appcast`。

### 公证失败

检查 notarytool profile 是否正确：

```bash
xcrun notarytool history --keychain-profile "liang-notary"
```

### Gatekeeper 仍拦截

确保 DMG 已 staple：

```bash
xcrun stapler validate build/Liang.dmg
```

并检查 app 签名：

```bash
spctl --assess -vv build/Liang.app
```

预期输出：

```
build/Liang.app: accepted
source=Notarized Developer ID
```
