## Apple Developer Program 操作步骤

### 第 1 步：注册（约 10 分钟，$99/年）

1. 打开 https://developer.apple.com/programs/
2. 点右上角 **Enroll**
3. 用你的 Apple ID 登录（建议用个人 Apple ID，不要新注册）
4. 填写个人信息（姓名、地址），选择 **Individual**（个人开发者）
5. 支付 **$99/年**
6. 等确认邮件（通常几分钟到几小时）

### 第 2 步：在 Xcode 中创建证书（约 5 分钟）

注册审核通过后：

1. 打开 **Xcode → Settings → Accounts**
2. 左下角 `+`，添加你的 Apple ID
3. 选中你的 Apple ID，点右侧 **Manage Certificates...**
4. 点 `+`，选 **Developer ID Application**
5. Xcode 自动生成并下载证书到钥匙串

验证：
```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 第 3 步：创建 App-Specific Password（公证用）

1. 打开 https://appleid.apple.com/
2. 登录 → **Sign-In and Security** → **App-Specific Passwords**
3. 点 `+`，名称填 `Liang Notarization`，记下生成的密码（格式 `xxxx-xxxx-xxxx-xxxx`）

或直接用命令行：
```bash
# 后面公证时直接用钥匙串，不需要单独创建密码
xcrun notarytool submit ... --keychain-profile "LIANG_NOTARY"
```

### 第 4 步：配置钥匙串 Profile（一次性的）

```bash
xcrun notarytool store-credentials "LIANG_NOTARY" \
    --apple-id "你的AppleID邮箱" \
    --team-id "你的Team ID" \
    --password "第3步的app-specific密码"
```

Team ID 查看：https://developer.apple.com/account → Membership → Team ID

### 第 5 步：改造 build-dmg.sh

不用你自己改，注册完告诉我，我来更新脚本。大致改动：

- 签名：`codesign --sign "Developer ID Application: 你的名字 (TeamID)" --options runtime --timestamp --deep`
- 公证：`xcrun notarytool submit Liang.dmg --keychain-profile "LIANG_NOTARY" --wait`
- 装订票据：`xcrun stapler staple Liang.dmg`

---

### 先做的 vs 后做的

| 现在就做 | 注册完成后做 |
|---|---|
| 第 1 步：注册开发者账号 | 第 2-4 步：证书 + 公证凭证 |
| 等审核通过（几小时） | 第 5 步：改造打包脚本 |
| | 后续：集成 Sparkle 2 自动更新 |

---

先去做第 1 步注册。审核通过后告诉我，我把签名、公证、Sparkle 2 一起加进去，一步到位。