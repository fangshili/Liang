# T8 测试脚本：稳定性优化

## 目标

验证 Liang 在长时间运行、睡眠/唤醒、Cursor 退出、事件文件异常等场景下保持稳定，不泄漏资源、不误报状态。

## 前置条件

1. 完成 T1–T7。
2. 已通过 `swift build`。
3. 已正确安装 Cursor Hooks 并能在运行时产生事件。

## 测试步骤

### A. 重复启动保护

1. 正常启动 Liang。
2. 模拟异常调用：在 `AppDelegate.applicationDidFinishLaunching` 里连续调用两次 `GlowController.shared.start()`、`StateEngine.shared.start()`、`CursorHookAdapter.shared.start()`（测试后还原）。
3. 期望：
   - 没有重复的状态刷新或重复事件消费。
   - 菜单栏状态正常，光晕正常。
   - Console 中不会重复打印 `GlowController.start()` / `StateEngine.start()` / `CursorHookAdapter.start()`。

### B. 睡眠/唤醒

1. 让 Cursor 处于 processing 状态，确认光晕为 processing 颜色。
2. 让 Mac 进入睡眠（可通过合盖或系统菜单）。
3. 唤醒 Mac。
4. 期望：
   - 睡眠期间光晕消失（不耗电）。
   - 唤醒后光晕恢复，并继续反映当前 Cursor 状态。

### C. 锁屏/解锁（可选）

1. 在 processing 状态下按 `Ctrl + Cmd + Q` 锁屏。
2. 解锁后观察光晕。
3. 期望：锁屏后光晕隐藏，解锁后恢复。

### D. 长时间无事件回到 idle

1. 让 Cursor 进入 processing 或 waiting 状态。
2. 完全退出 Cursor（Cmd+Q），不再产生新事件。
3. 等待 5 分钟（默认 `sessionIdleTimeout`）。
4. 期望：
   - 5 分钟后光晕自动回到 idle 颜色。
   - 菜单栏显示最近事件时间，状态为 idle。

### E. 事件文件被清空/轮转

1. 启动 Liang 并确认正在接收 Cursor 事件。
2. 执行：
   ```bash
   > ~/.liang/cursor-events.jsonl
   ```
   清空事件文件。
3. 继续触发新的 Cursor 事件。
4. 期望：
   - 清空后 Adapter 能自动重连（ health check 30 秒一次）。
   - 新事件仍能被 Liang 接收并正确映射状态。

### F. Cursor 退出与重启

1. 启动 Cursor 并产生 processing 事件。
2. 完全退出 Cursor，等待 5 分钟。
3. 期望：光晕回到 idle。
4. 重新启动 Cursor，发送一条新消息。
5. 期望：Liang 重新进入 processing，无需重启 Liang。

### G. 低电量/ reduce motion

1. 系统偏好设置 → 辅助功能 → 显示 → 勾选「减少动态效果」。
2. 让 Cursor 进入 processing。
3. 期望：光晕变为静态（无呼吸动画）。
4. 取消勾选，期望动画恢复。

### H. 日志检查

1. 打开 Console.app，过滤 `com.liang`。
2. 正常使用 Liang 一段时间。
3. 期望：
   - 不再有大量 `print` 输出。
   - debug 级别日志不再出现（Release 默认不收集 debug）。
   - 关键事件（状态转换、文件重连、睡眠/唤醒）有 info 级别日志。

## 通过标准

- [ ] 重复启动不产生重复订阅。
- [ ] 睡眠/唤醒光晕正确隐藏与恢复。
- [ ] 5 分钟无事件从 processing/waiting 回到 idle。
- [ ] 事件文件被清空后自动重连并继续工作。
- [ ] Cursor 退出并重启后无需重启 Liang。
- [ ] reduce motion / 低电量下动画降级为静态。
- [ ] 日志分级正确，无 spam。
- [ ] `swift build` 无错误。
