# T10 测试脚本：Onboarding v2

## 目标

验证两步骤 Onboarding 流程在首次启动 / 非首次启动场景下的行为、光晕动画自动循环、Cursor 配置引导集成，以及「完成 Onboarding」的状态持久化。

## 前置条件

1. 完成 T1–T8。
2. `swift build` 通过。
3. 删除本地配置模拟首次启动：
   ```bash
   defaults delete com.liang.settings.v1 2>/dev/null || true
   rm -rf ~/Library/Application\ Support/Liang 2>/dev/null || true
   ```
4. 清空 Cursor Hooks 配置（首次启动体验不需要）：
   ```bash
   rm -f ~/.cursor/hooks.json
   rm -rf ~/.cursor/hooks/liang-bridge.sh
   ```

## 测试步骤

### A. 首次启动显示 Onboarding Step 1

1. 启动 Liang (`swift run Liang` 或 `open .build/debug/Liang`)。
2. 期望：
   - 自动弹出无边框深色窗口，标题「Liang」。
   - 窗口大小 760×560，居中显示。
   - 顶部 Logo「Liang」+ 步骤指示器 `1 / 2`。
   - 主区域：标题「Connect a Coding Agent」+ 副标题。
   - Cursor 主卡片：蓝色边框图标，状态文字 `Not configured`。
   - 卡片下方按钮「Cursor  →」（蓝色渐变）。
   - 「Other agents」段落：`Claude Code · Codex CLI · CodeBuddy · Trae` 灰字 + `Coming soon...`。
   - 底部：「Maybe later」「Next  →」两个按钮。

### B. Step 1 弹窗引导

1. 点击 Cursor 卡片上的「Cursor  →」按钮。
2. 期望：
   - 弹出深色 overlay，包含已有的 `CursorSetupSection` 内容。
   - overlay 上有 ✕ 关闭按钮。
   - 点击 overlay 外部不会触发关闭。
3. 选择「自动安装」并等待完成。
4. 期望：
   - CursorSetupSection 状态变为 `已配置 (script path 脚本路径)`。
5. 点 ✕ 关闭 overlay。
6. 期望：
   - 自动回到 Step 1。
   - Cursor 卡片边框变绿、出现 ✓ 标记和「Connected」徽章。
   - 卡片底部按钮变为「Connected」灰色标签（不可点击）。
   - 用户无需手动点 Next，已能继续。

### C. Step 1 → Step 2 切换

1. 点击「Next  →」。
2. 期望：
   - 步骤指示器变为 `1 → 2`（蓝色点→绿色 ✓）。
   - 主区域变为 Step 2：标题「Choose your glow」+ 副标题 + 右上角「● Auto-preview · looping」标签。
   - 三张光晕卡片从上到下：Notch Glow、Cursor Glow、Menu Bar Status Color。
   - 每张卡片左侧 200×132pt 的预览图，右侧文字说明 + Toggle 开关。
   - 动画播放：
     - 三种光晕依次（每张约 9s）作为 active。
     - 每张内部状态按 `IDLE → PROCESSING → SUCCESS` 循环，每态约 3 秒。
     - 状态色：橙、蓝、绿。
     - 状态色变更时预览卡片边框颜色和右下角状态徽章同步变化。
     - 非活跃卡片无动画，活跃卡片有呼吸/glow 动画。

### D. Step 2 默认勾选

有刘海 Mac：
- Notch Glow toggle = ON
- Cursor Glow toggle = OFF
- Menu Bar Status toggle = OFF

无刘海 Mac：
- Notch Glow 卡片禁用（toggle 灰），下方出现「Not available on this Mac」提示。
- Cursor Glow toggle = OFF
- Menu Bar Status toggle = ON

### E. 实时切换 Toggle

1. 在 Step 2 任意时刻，点击某卡片右侧 Toggle。
2. 期望：
   - 对应 settings 属性（`glowEnabled` / `cursorGlowEnabled` / `menuBarStateColorEnabled`）即改变。
   - 重新启动 Liang 后，toggle 状态保持一致。
   - 当前真实光晕（刘海/光标/菜单栏）状态也跟随变化。

### F. 直接完成

在 Step 2 正在循环动画时点击「Start Using Liang  →」。
期望：
- 窗口立即关闭。
- 设置 `hasCompletedOnboarding = true`（`defaults read com.liang.settings.v1 | grep onboarding` 可见）。
- 后续启动 Liang 不再显示 Onboarding 窗口。

### G. Step 2 → Step 1 返回

1. 在 Step 2，点击「←  Back」。
2. 期望：
   - 步骤指示器回到 `1 / 2`。
   - 主区域回到 Step 1。
   - 之前在 Step 2 切换的 toggle 状态保留。

### H. 非首次启动：跳过 Step 1

1. 在 `defaults` 中手动标记 Cursor 已配置（模拟通过设置页配置）：
   ```bash
   defaults write com.liang.settings.v1 hasCompletedCursorSetup -bool true
   ```
2. 重启 Liang。
3. 期望：
   - Onboarding 窗口仍然短暂出现一次，但**直接停留在 Step 2**。
   - 步骤指示器显示 `2 / 2`。
   - 三种光晕自动循环动画立即开始。
   - 没有 Step 1 提示。

### I. 已完成的非首次启动：跳过整个 Onboarding

1. 在 `defaults` 中标记：
   ```bash
   defaults write com.liang.settings.v1 hasCompletedOnboarding -bool true
   ```
2. 重启 Liang。
3. 期望：
   - **不再弹出** Onboarding 窗口。
   - Liang 正常进入菜单栏和光晕模式。
   - Console 中看到 `OnboardingWindowController` 没有 `windowDidLoad` 日志。

### J. 多 Coding Agent 检测（接口预留）

当前仅 Cursor 真正接入，但 `hasAnyConnectedAgent` 检查已按 IDE 维度实现：
1. 重置 `hasCompletedOnboarding = false`。
2. 设置 `defaults write com.liang.settings.v1 ideEnabled.cursor -bool false` 关闭 Cursor。
3. 直接修改 `hasCompletedCursorSetup = false`。
4. 重启 Liang。
5. 期望：
   - Onboarding 显示 Step 1。
   - 这意味着未来接入 Claude Code 等 Coding Agent 后，只要任一 IDE 启用即可跳过 Step 1。

### K. 关闭按钮

1. 在任意 Step 中点击窗口关闭按钮（X）。
2. 期望：
   - 窗口消失但 `hasCompletedOnboarding` **未**被设置（视为用户取消，不视作完成）。
   - 下次启动会再次弹出 Onboarding。

## 通过标准

- [ ] 首次启动自动弹出 Onboarding 的 Step 1。
- [ ] Step 1 Cursor 卡片在未配置时显示「Not configured」。
- [ ] 配置完成后自动显示「Connected」状态，无需手动刷新。
- [ ] Step 2 自动循环展示三种光晕（idle → processing → success 各 3s）。
- [ ] Toggle 实时绑定 settings 持久化字段。
- [ ] 无刘海时 Notch Glow 卡片禁用并标注「Not available on this Mac」。
- [ ] Step 2 可直接点「Start Using Liang」完成。
- [ ] 步进指示器在 Step 1 / Step 2 之间正确切换。
- [ ] 「Any connected Coding Agent」即可跳过 Step 1（当前等价于 Cursor 已配置）。
- [ ] Onboarding 完成后再次启动 Liang 不会重弹窗口。
- [ ] 关闭 X 按钮视为取消，不持久化完成状态。
- [ ] 中文环境下显示对应中文文案（`/Library/Application Support/Liang/i18n`）。
- [ ] `swift build` 无错误无警告。
