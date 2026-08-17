import Cocoa
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "CursorGlowController")

/// 跟随鼠标光标的小光晕控制器，与刘海光晕保持颜色和动画同步。
final class CursorGlowController {
    static let shared = CursorGlowController()
    let settings = GlowSettings.shared
    private let window = CursorGlowWindow()
    private let labelWindow = CursorLabelWindow()
    private var cancellables = Set<AnyCancellable>()
    private var currentState: LiangState = .idle
    private var isStarted = false
    private var isAsleep = false
    private var mouseTimer: Timer?
    private var lastWindowFrame: CGRect?
    private var lastLabelFrame: CGRect?

    /// 仅用于 onboarding 预览：强制把光标光晕显示出来，不影响用户的 `cursorGlowEnabled` 设置。
    var previewForceShow: Bool = false {
        didSet {
            guard previewForceShow != oldValue else { return }
            if previewForceShow {
                startMouseTimer()
                update()
            } else {
                // 不再预览时，按用户设置决定是否停掉鼠标轮询和窗口
                if settings.cursorGlowEnabled {
                    update()
                } else {
                    stopMouseTimer()
                    window.orderOut(nil)
                    labelWindow.orderOut(nil)
                }
            }
        }
    }

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        logger.info("CursorGlowController.start()")

        settings.$cursorGlowEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.startMouseTimer()
                    self?.update()
                } else {
                    self?.stopMouseTimer()
                    self?.window.orderOut(nil)
                    self?.labelWindow.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        settings.$cursorLabelEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        settings.$cursorGlowSize.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.update() }.store(in: &cancellables)
        settings.$cursorGlowOffsetX.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.update() }.store(in: &cancellables)
        settings.$cursorGlowOffsetY.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.update() }.store(in: &cancellables)
        settings.$brightness.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$stateColors.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$stateGlowEnabled.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)

        StateEngine.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.currentState = state
                self?.apply()
            }
            .store(in: &cancellables)

        GlowController.shared.previewStateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.apply()
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

        if settings.cursorGlowEnabled {
            startMouseTimer()
            update()
        }
    }

    @objc private func systemWillSleep() {
        logger.info("Cursor glow hiding for sleep / screen off")
        isAsleep = true
        window.orderOut(nil)
        labelWindow.orderOut(nil)
    }

    @objc private func systemDidWake() {
        logger.info("Cursor glow restoring after wake / screen on")
        isAsleep = false
        if settings.cursorGlowEnabled {
            update()
        }
    }

    private func startMouseTimer() {
        stopMouseTimer()
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    private func stopMouseTimer() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }

    @objc private func update() {
        if !previewForceShow {
            guard settings.cursorGlowEnabled, !isAsleep else {
                window.orderOut(nil)
                return
            }
        }
        updatePosition()
        apply()
        window.orderFront(nil)
    }

    @objc func apply() {
        if !previewForceShow {
            guard settings.cursorGlowEnabled, !isAsleep else {
                window.orderOut(nil)
                labelWindow.orderOut(nil)
                return
            }
        }

        let displayState = GlowController.shared.previewState ?? currentState
        guard let appearance = displayState.appearance(using: settings) else {
            window.orderOut(nil)
            labelWindow.orderOut(nil)
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let motionEnabled = !reduceMotion && !lowPower
        let animationMode: StateAppearance.AnimationMode = motionEnabled ? appearance.mode : .steady

        logger.debug("cursor apply state=\(String(describing: displayState)) mode=\(String(describing: animationMode))")
        window.apply(settings: settings, color: appearance.color, animationMode: animationMode)
        window.orderFront(nil)

        labelWindow.apply(state: displayState, color: appearance.color, enabled: settings.cursorLabelEnabled)
        if labelWindow.isVisible {
            updateLabelPosition()
        }
    }

    private func updatePosition() {
        if !previewForceShow {
            guard settings.cursorGlowEnabled, !isAsleep else { return }
        }

        let mouse = NSEvent.mouseLocation
        let size = windowSize()
        let offsetX = CGFloat(settings.cursorGlowOffsetX)
        let offsetY = CGFloat(settings.cursorGlowOffsetY)

        var origin = CGPoint(
            x: mouse.x + offsetX - size.width / 2,
            y: mouse.y + offsetY - size.height / 2
        )

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            origin.x = max(screen.frame.minX, min(origin.x, screen.frame.maxX - size.width))
            origin.y = max(screen.frame.minY, min(origin.y, screen.frame.maxY - size.height))
        }

        let frame = CGRect(origin: origin, size: size)
        if frame != lastWindowFrame {
            lastWindowFrame = frame
            window.setFrame(frame, display: true)
        }

        if labelWindow.isVisible {
            updateLabelPosition()
        }
    }

    private func updateLabelPosition() {
        // 预览模式下即使 cursorGlowEnabled 未开启，也要更新标签位置，
        // 否则用户悬停在 onboarding Step 2 卡片上看不到光标状态文字。
        guard settings.cursorLabelEnabled, !isAsleep else { return }
        guard previewForceShow || settings.cursorGlowEnabled else { return }

        let mouse = NSEvent.mouseLocation
        let offsetX = CGFloat(settings.cursorGlowOffsetX)
        let offsetY = CGFloat(settings.cursorGlowOffsetY)
        let glowRadius = CGFloat(settings.cursorGlowSize) / 2
        let labelSize = labelWindow.frame.size
        let gap: CGFloat = 8

        var origin = CGPoint(
            x: mouse.x + offsetX + glowRadius + gap,
            y: mouse.y + offsetY - labelSize.height / 2
        )

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            origin.x = max(screen.frame.minX, min(origin.x, screen.frame.maxX - labelSize.width))
            origin.y = max(screen.frame.minY, min(origin.y, screen.frame.maxY - labelSize.height))
        }

        let frame = CGRect(origin: origin, size: labelSize)
        if frame != lastLabelFrame {
            lastLabelFrame = frame
            labelWindow.setFrame(frame, display: true)
        }
    }

    private func windowSize() -> CGSize {
        let diameter = CGFloat(settings.cursorGlowSize)
        // 窗口大小 == 光晕直径的两倍，给径向渐变留出从中心到完全透明的过渡空间。
        return CGSize(width: diameter * 2, height: diameter * 2)
    }
}
