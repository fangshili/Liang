# 刘海展开动效 — 代码方法汇总

鼠标移动到刘海处展开面板区域的交互，由以下两个文件协作实现：

- `Sources/Liang/NotchExpansionController.swift` —— 控制器：hover 检测、窗口定位、展开/折叠状态切换
- `Sources/Liang/NotchExpansionWindow.swift` —— 渲染层：用 `CAShapeLayer` 的 path 形变实现动画

---

## 一、NotchExpansionController.swift（控制器）

### 核心状态属性
| 属性 | 类型 | 作用 |
|---|---|---|
| `window` | `NotchExpansionWindow` | 被管理的展开窗口 |
| `mouseTimer` | `Timer?` | 30fps 轮询鼠标位置的定时器 |
| `isStarted` / `isAsleep` | `Bool` | 启动保护 / 睡眠态标记 |
| `isExpanded` | `Bool` | 当前是否展开（状态翻转才触发动画） |
| `currentAnchor` | `CGRect?` | 刘海热区在屏幕坐标中的位置 |
| `expandedSize` | `CGSize?` | 展开后的面板尺寸 |
| `expandedHeight` | `CGFloat = 200` | 展开后向下延伸高度 |
| `expandedExtraWidth` | `CGFloat = 192` | 展开后左右各放宽（共 96pt × 2） |

### 方法列表

#### `func start()`
入口方法。做四件事：
1. 监听 `didChangeScreenParameters`（屏幕参数变化，如接拔显示器）；
2. 监听 `willSleep` / `screensDidSleep` / `didWake` / `screensDidWake`；
3. 订阅 `settings.$notchExpansionEnabled` 开关变化（开 → `show()`，关 → `orderOut` + 停定时器）；
4. 订阅 `settings.$cornerRadiusScale` 变化（无动画重绘）；
5. 若默认开启则立即 `show()`。

#### `@objc private func update()`
响应屏幕参数变化通知：重算锚点、无动画重绘、置顶显示；睡眠或关闭展开时隐藏并停定时器。

#### `private func show()`
启用展开：重算锚点 → 无动画应用 → `orderFront` → `startMouseTimer()`。

#### `private func updateAnchor()`
根据当前主屏计算 `currentAnchor` 与 `expandedSize`：
- **有刘海**：热区与硬件刘海完全对齐（`DeviceCapability.notchMetrics`），方便鼠标从下方滑入；展开尺寸 = 刘海宽 + `expandedExtraWidth`。
- **无刘海**：用顶部中央 40×14 的"假刘海"造型作为热区与展开起点。

#### `private func startMouseTimer()` / `stopMouseTimer()`
启动/停止 30fps（`1.0/30.0`）轮询定时器。每次 tick 调 `checkHover()`。

#### `private func checkHover()`
hover 检测核心：
- 取 `NSEvent.mouseLocation`；
- 热区 = 已展开用整块面板矩形 `expandedRect(for:)`，未展开用刘海本身 `anchor`；
- `hotRect.contains(mouse)` 与 `isExpanded` 不同 → 翻转状态并 `apply(animated: true)`。
- 注意：用全局坐标轮询而非 `NSTrackingArea`，因为硬件刘海区常规 tracking area 无法覆盖。

#### `private func expandedRect(for anchor: CGRect) -> CGRect`
计算展开后的命中矩形（锚点 + 向下延伸 `expandedSize.height`，宽度 `expandedSize.width`），供展开态下保持鼠标在面板内不回弹。

#### `private func apply(animated: Bool)`
把当前 `currentAnchor` / `expandedSize` / `isExpanded` / `cornerRadiusScale` 传给 `window.update(...)`，再 `orderFront`。

#### `@objc private func systemWillSleep()` / `systemDidWake()`
睡眠/关屏：隐藏窗口、停定时器、`isExpanded=false`；唤醒后若启用则 `show()` 恢复。

---

## 二、NotchExpansionWindow.swift（渲染层）

### 结构
- `shapeLayer: CAShapeLayer` —— 黑色填充的形状层，所有动画作用于它的 `path`。
- 窗口为 `borderless` + `nonactivatingPanel`，`ignoresMouseEvents = true`（纯视觉），`level = mainMenu+2`（压在刘海之上），`collectionBehavior = [.canJoinAllSpaces, .stationary]`。
- `shapeLayer.actions = ["path": NSNull()]` —— 禁用隐式动画，仅由显式动画控制。

### 方法列表

#### `init()`
初始化窗口：透明、无激活、置顶、忽略鼠标；内容视图加一个 `CAShapeLayer`（黑填充）作为形状层。

#### `func update(anchor:expandedHeight:expandedWidth:cornerRadiusScale:isExpanded:animated:)`
核心绘制 + 动画入口：
1. 按锚点 + 展开尺寸算 `windowFrame` 并 `setFrame`；
2. 设 `shapeLayer.frame`；
3. 底部圆角 `bottomRadius = min(notchHeight * cornerRadiusScale, 12)`，随刘海弧度走，不随面板放大；
4. 调用 `shapePath(...)` 算目标路径 `newPath`；
5. **动画分支**：若 `animated` 且已有 `oldPath`，建 `CABasicAnimation(keyPath: "path")`，`duration = 0.4`，`timingFunction = .easeInEaseOut`，`fillMode = .forwards`，`isRemovedOnCompletion = false`；否则直接赋值。

#### `private func shapePath(in:topWidth:notchHeight:isExpanded:bottomCornerRadius:) -> CGPath`
用贝塞尔曲线画出形状：
- **折叠**（`isExpanded=false`）：`panelHalfWidth = 刘海半宽`、`flareDepth = 0`、`panelBottomY = 底部` → 画出来就是贴着顶边的刘海轮廓。
- **展开**（`isExpanded=true`）：`panelHalfWidth = 窗口半宽`、`flareDepth = 36`（向下外扩弧线）、`panelBottomY = 顶部` → 向下展开成带圆角和下扩弧线的面板。
- 路径顺序：顶边 → 沿刘海右侧下到刘海底角 → 右扩曲线到面板右侧 → 右侧直边 → 右下圆角 → 底边 → 左下圆角 → 左侧直边 → 左收曲线回刘海底角 → 沿左侧上回到顶边 → 闭合。

---

## 三、动效原理一句话

透明 borderless 窗口常驻刘海上方；控制器以 30fps 轮询鼠标全局坐标判断是否命中热区（折叠命中刘海、展开命中整块面板）；状态翻转时，对 `CAShapeLayer` 的 `path` 做 0.4s `easeInEaseOut` 补间，从「刘海轮廓」形变成「带圆角与下扩弧线的面板」。

## 四、触发与生命周期

- 总开关：`GlowSettings.notchExpansionEnabled`（设置页可配）。
- 屏幕参数变化：`update()` 重算并复位。
- 睡眠/唤醒/关屏：自动隐藏与恢复（`systemWillSleep` / `systemDidWake`）。
- 圆角跟随设置：`GlowSettings.cornerRadiusScale`。

## 五、当前状态备注

`NotchExpansionWindow` 目前只渲染一个黑色形状层，**尚未在展开区域内塞入任何内容视图**（无实际 UI 内容）。如需在展开面板内显示信息，需在 `NotchExpansionWindow` 的内容视图层接入子视图，并随 `isExpanded` 状态显隐。
