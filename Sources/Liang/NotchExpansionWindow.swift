import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "NotchExpansionWindow")

/// 刘海/顶部展开面板窗口。
/// 窗口尺寸固定为展开后大小，通过 CAShapeLayer 的 path 动画实现从隐藏锚点到面板的平滑形变。
final class NotchExpansionWindow: NSWindow {
    private let shapeLayer = CAShapeLayer()
    private let contentContainer = NSView()
    private let scrollView = NSScrollView()
    private let listContainer = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var contentShowWorkItem: DispatchWorkItem?
    private var isExpanded = false

    /// 让 documentView 使用 y=0 在顶部的坐标系，列表自然从上往下排。
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
    private var cancellables = Set<AnyCancellable>()
    private var currentSettings: GlowSettings?

    /// 顶部锚点高度（刘海高度），用于计算内容区域顶部内边距。
    private var anchorHeight: CGFloat = 0

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .init(NSWindow.Level.mainMenu.rawValue + 2)
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        contentView = container

        shapeLayer.fillColor = NSColor.black.cgColor
        shapeLayer.actions = ["path": NSNull()] // 禁用隐式动画，由显式动画控制
        container.layer?.addSublayer(shapeLayer)

        setupContentContainer(in: container)
        bindTasks()
    }

    private func setupContentContainer(in container: NSView) {
        contentContainer.wantsLayer = true
        contentContainer.alphaValue = 0
        container.addSubview(contentContainer)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        contentContainer.addSubview(scrollView)

        listContainer.wantsLayer = true
        listContainer.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.documentView = listContainer

        emptyLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.isBordered = false
        emptyLabel.backgroundColor = .clear
        emptyLabel.stringValue = I18n.shared.string(.noRunningTasks)
        contentContainer.addSubview(emptyLabel)
    }

    private func bindTasks() {
        StateEngine.shared.$recentTasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadTasks() }
            .store(in: &cancellables)
    }

    private func reloadTasks() {
        let tasks = StateEngine.shared.orderedTasks

        // 移除旧行。
        listContainer.subviews.forEach { $0.removeFromSuperview() }

        guard !tasks.isEmpty else {
            listContainer.isHidden = true
            emptyLabel.isHidden = false
            return
        }

        listContainer.isHidden = false
        emptyLabel.isHidden = true

        let rowHeight: CGFloat = 36
        let totalHeight = CGFloat(tasks.count) * rowHeight
        for (index, task) in tasks.enumerated() {
            let row = TaskRowView(frame: NSRect(
                x: 0,
                y: CGFloat(index) * rowHeight,
                width: listContainer.frame.width,
                height: rowHeight
            ))
            row.task = task
            row.autoresizingMask = [.width]
            listContainer.addSubview(row)
        }

        listContainer.frame = CGRect(x: 0, y: 0, width: listContainer.frame.width, height: totalHeight)
    }

    /// 更新窗口位置与形状。
    /// - Parameters:
    ///   - anchor: 顶部锚点区域在屏幕坐标中的位置（用于计算形状顶部宽度）。
    ///   - expandedHeight: 展开后向下延伸的高度。
    ///   - expandedWidth: 展开后的宽度。
    ///   - cornerRadiusScale: 底部圆角比例（来自设置）。
    ///   - isExpanded: 当前是否展开。
    ///   - animated: 是否使用动画。
    func update(
        anchor: CGRect,
        expandedHeight: CGFloat,
        expandedWidth: CGFloat,
        cornerRadiusScale: Double,
        isExpanded: Bool,
        animated: Bool
    ) {
        self.isExpanded = isExpanded

        let windowHeight = anchor.height + expandedHeight
        let windowFrame = CGRect(
            x: anchor.midX - expandedWidth / 2,
            y: anchor.maxY - windowHeight,
            width: expandedWidth,
            height: windowHeight
        )
        setFrame(windowFrame, display: true)

        shapeLayer.frame = CGRect(origin: .zero, size: windowFrame.size)
        anchorHeight = anchor.height

        // 内容容器占据展开区域（窗口底部到刘海下沿）。
        contentContainer.frame = CGRect(x: 0, y: 0, width: windowFrame.width, height: expandedHeight)
        scrollView.frame = contentContainer.bounds
        let documentHeight = max(listContainer.frame.height, scrollView.bounds.height)
        listContainer.frame = CGRect(x: 0, y: 0, width: scrollView.bounds.width, height: documentHeight)

        // 空状态标签居中。
        let emptySize = emptyLabel.sizeThatFits(NSSize(width: scrollView.bounds.width - 32, height: expandedHeight))
        emptyLabel.frame = CGRect(
            x: 16,
            y: (expandedHeight - emptySize.height) / 2,
            width: scrollView.bounds.width - 32,
            height: emptySize.height
        )

        // 底部圆角：折叠时与刘海底部圆角一致（≤12），展开时线性放大到 2 倍（≤24）。
        let notchHeight = DeviceCapability.notchMetrics?.height ?? anchor.height
        let compactRadius = min(notchHeight * CGFloat(cornerRadiusScale), 12)
        let expandedRadius = min(compactRadius * 2, 24)
        let bottomRadius = isExpanded ? expandedRadius : compactRadius
        let newPath = shapePath(
            in: shapeLayer.bounds,
            topWidth: anchor.width,
            notchHeight: notchHeight,
            isExpanded: isExpanded,
            bottomCornerRadius: bottomRadius
        )

        if animated, let oldPath = shapeLayer.path {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = oldPath
            animation.toValue = newPath
            animation.duration = 0.4
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            shapeLayer.add(animation, forKey: "path")
        }
        shapeLayer.path = newPath

        // 展开时允许鼠标交互（滚动列表），收起时穿透鼠标。
        ignoresMouseEvents = !isExpanded

        // 内容淡入淡出：展开时等形状动画展开到一半再淡入；收起时立即隐藏。
        contentShowWorkItem?.cancel()
        contentShowWorkItem = nil
        if isExpanded {
            contentContainer.alphaValue = 0
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isExpanded else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    self.contentContainer.animator().alphaValue = 1
                }
            }
            contentShowWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        } else {
            contentContainer.alphaValue = 0
        }

        logger.debug("notch expansion updated: expanded=\(isExpanded), frame=\(String(describing: windowFrame))")
    }

    private func shapePath(
        in bounds: CGRect,
        topWidth: CGFloat,
        notchHeight: CGFloat,
        isExpanded: Bool,
        bottomCornerRadius: CGFloat
    ) -> CGPath {
        let midX = bounds.midX
        let panelBottomY = isExpanded ? bounds.minY : bounds.maxY - notchHeight
        let panelHeight = bounds.maxY - panelBottomY

        // 顶部“耳朵”宽度：模仿 HTML 模拟器里的屏幕顶角内收弧度。
        let ear: CGFloat = min(max(notchHeight * 0.35, 10), 16)
        let cp = ear * 0.55

        // 折叠时形状宽度等于刘海宽度，隐藏在刘海后；展开时撑满窗口。
        let panelLeft = isExpanded ? bounds.minX : midX - topWidth / 2
        let panelRight = isExpanded ? bounds.maxX : midX + topWidth / 2
        let sideLeft = panelLeft + ear
        let sideRight = panelRight - ear
        let topY = bounds.maxY
        let earBottomY = topY - ear

        let bottomRadius = min(bottomCornerRadius, panelHeight / 2, (sideRight - sideLeft) / 2)

        let path = CGMutablePath()

        // 左上角耳朵：从屏幕顶角内收到面板左侧。
        path.move(to: CGPoint(x: panelLeft, y: topY))
        path.addCurve(
            to: CGPoint(x: sideLeft, y: earBottomY),
            control1: CGPoint(x: panelLeft + cp, y: topY),
            control2: CGPoint(x: sideLeft, y: earBottomY + cp)
        )
        // 左侧直边。
        path.addLine(to: CGPoint(x: sideLeft, y: panelBottomY + bottomRadius))
        // 左下角圆角。
        path.addQuadCurve(
            to: CGPoint(x: sideLeft + bottomRadius, y: panelBottomY),
            control: CGPoint(x: sideLeft, y: panelBottomY)
        )
        // 底边。
        path.addLine(to: CGPoint(x: sideRight - bottomRadius, y: panelBottomY))
        // 右下角圆角。
        path.addQuadCurve(
            to: CGPoint(x: sideRight, y: panelBottomY + bottomRadius),
            control: CGPoint(x: sideRight, y: panelBottomY)
        )
        // 右侧直边。
        path.addLine(to: CGPoint(x: sideRight, y: earBottomY))
        // 右上角耳朵：从面板右侧内收到屏幕右上角。
        path.addCurve(
            to: CGPoint(x: panelRight, y: topY),
            control1: CGPoint(x: sideRight, y: earBottomY + cp),
            control2: CGPoint(x: panelRight - cp, y: topY)
        )
        path.closeSubpath()
        return path
    }
}
