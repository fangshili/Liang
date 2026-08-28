import Cocoa
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "NotchExpansionController")

/// 管理刘海/顶部展开面板的 hover 检测与动画。
final class NotchExpansionController {
    static let shared = NotchExpansionController()
    let settings = GlowSettings.shared
    private let window = NotchExpansionWindow()
    private var cancellables = Set<AnyCancellable>()
    private var mouseTimer: Timer?
    private var isStarted = false
    private var isAsleep = false
    private var isExpanded = false
    private var currentAnchor: CGRect?
    private var expandedSize: CGSize?

    private let expandedHeight: CGFloat = 200
    private let expandedExtraWidth: CGFloat = 240 // 展开后左右各放宽 120pt，紧凑但够容纳任务标题

    /// 是否应显示展开面板：开关开启，且（有刘海 或 非刘海未隐藏假刘海）。
    private var shouldShowExpansion: Bool {
        guard settings.notchExpansionEnabled else { return false }
        if !DeviceCapability.hasNotchedScreen && settings.hideFakeNotch { return false }
        return true
    }

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        logger.info("NotchExpansionController.start()")

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemWillSleep()
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemDidWake()
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemWillSleep()
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemDidWake()
        }

        settings.$notchExpansionEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)

        settings.$hideFakeNotch
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)

        settings.$cornerRadiusScale
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply(animated: false) }
            .store(in: &cancellables)

        if shouldShowExpansion {
            show()
        }
    }

    @objc private func update() {
        guard shouldShowExpansion, !isAsleep else {
            window.orderOut(nil)
            stopMouseTimer()
            return
        }
        updateAnchor()
        apply(animated: false)
        window.orderFront(nil)
    }

    private func show() {
        guard shouldShowExpansion, !isAsleep else { return }
        updateAnchor()
        apply(animated: false)
        window.orderFront(nil)
        startMouseTimer()
    }

    private func applyVisibility() {
        if shouldShowExpansion {
            show()
        } else {
            window.orderOut(nil)
            stopMouseTimer()
        }
    }

    private func updateAnchor() {
        guard let screen = DeviceCapability.primaryNotchedScreen ?? NSScreen.main ?? NSScreen.screens.first else {
            currentAnchor = nil
            expandedSize = nil
            return
        }

        if screen.hasNotch, let metrics = DeviceCapability.notchMetrics {
            // hover 热区与硬件刘海完全对齐，方便鼠标从下方滑入刘海区域时触发。
            let anchorWidth = metrics.width
            let anchorHeight = metrics.height
            let anchorY = screen.frame.maxY - anchorHeight
            currentAnchor = CGRect(
                x: screen.frame.midX - anchorWidth / 2,
                y: anchorY,
                width: anchorWidth,
                height: anchorHeight
            )
            expandedSize = CGSize(width: metrics.width + expandedExtraWidth, height: expandedHeight)
        } else {
            // 无刘海：顶部中央小刘海造型。
            let fakeWidth: CGFloat = 40
            let fakeHeight: CGFloat = 14
            currentAnchor = CGRect(
                x: screen.frame.midX - fakeWidth / 2,
                y: screen.frame.maxY - fakeHeight,
                width: fakeWidth,
                height: fakeHeight
            )
            expandedSize = CGSize(width: fakeWidth + expandedExtraWidth, height: expandedHeight)
        }
    }

    private func startMouseTimer() {
        guard mouseTimer == nil else { return }
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.checkHover()
        }
    }

    private func stopMouseTimer() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }

    private func checkHover() {
        guard shouldShowExpansion, !isAsleep, let anchor = currentAnchor else { return }
        let mouse = NSEvent.mouseLocation
        let hotRect = isExpanded ? expandedRect(for: anchor) : anchor
        let shouldExpand = hotRect.contains(mouse)

        if shouldExpand != isExpanded {
            isExpanded = shouldExpand
            apply(animated: true)
        }
    }

    private func expandedRect(for anchor: CGRect) -> CGRect {
        guard let size = expandedSize else { return anchor }
        let windowHeight = anchor.height + size.height
        return CGRect(
            x: anchor.midX - size.width / 2,
            y: anchor.maxY - windowHeight,
            width: size.width,
            height: windowHeight
        )
    }

    private func apply(animated: Bool) {
        guard let anchor = currentAnchor, let size = expandedSize else {
            window.orderOut(nil)
            return
        }
        window.update(
            anchor: anchor,
            expandedHeight: size.height,
            expandedWidth: size.width,
            cornerRadiusScale: settings.cornerRadiusScale,
            isExpanded: isExpanded,
            animated: animated
        )
        window.orderFront(nil)
    }

    @objc private func systemWillSleep() {
        logger.info("Notch expansion hiding for sleep / screen off")
        isAsleep = true
        isExpanded = false
        window.orderOut(nil)
        stopMouseTimer()
    }

    @objc private func systemDidWake() {
        logger.info("Notch expansion restoring after wake")
        isAsleep = false
        if shouldShowExpansion {
            show()
        }
    }
}
