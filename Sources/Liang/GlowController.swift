import Cocoa
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "GlowController")

final class GlowController {
    static let shared = GlowController()
    let settings = GlowSettings.shared
    private let window = GlowWindow()
    private var cancellables = Set<AnyCancellable>()
    private var currentState: LiangState = .idle
    private var isStarted = false
    private var isAsleep = false

    /// 设置页颜色编辑预览状态。非 nil 时，光晕强制显示该状态的颜色，忽略真实状态。
    /// 通过 subject 同步给 CursorGlowController，保证两处光晕一致。
    var previewState: LiangState? {
        didSet { previewStateSubject.send(previewState) }
    }
    let previewStateSubject = CurrentValueSubject<LiangState?, Never>(nil)

    /// 仅用于 onboarding 预览：强制把刘海光晕显示出来，不影响用户的 `glowEnabled` 设置。
    var previewForceShowNotch: Bool = false {
        didSet {
            guard previewForceShowNotch != oldValue else { return }
            if previewForceShowNotch {
                startPreviewWindow()
            } else {
                update()
            }
        }
    }

    private func startPreviewWindow() {
        guard !isAsleep else { return }
        window.updateFrame()
        apply()
        window.orderFront(nil)
    }

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        logger.info("GlowController.start()")

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
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

        settings.$brightness.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$blurRadius.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$outerThickness.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$innerThickness.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$notchInset.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.update() }.store(in: &cancellables)
        settings.$horizontalOffset.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.update() }.store(in: &cancellables)
        settings.$cornerRadiusScale.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$breathingEnabled.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$breathingSpeed.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        settings.$stateColors.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)

        settings.$glowEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.update()
                } else {
                    self?.window.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        StateEngine.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.currentState = state
                self?.apply()
            }
            .store(in: &cancellables)

        previewStateSubject
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.apply()
            }
            .store(in: &cancellables)

        if settings.glowEnabled {
            update()
        }

        NotchExpansionController.shared.start()
    }

    @objc private func systemWillSleep() {
        logger.info("System will sleep / screen off: hiding glow")
        isAsleep = true
        window.orderOut(nil)
    }

    @objc private func systemDidWake() {
        logger.info("System did wake / screen on: restoring glow")
        isAsleep = false
        if settings.glowEnabled {
            update()
        }
    }

    @objc private func update() {
        logger.info("GlowController.update()")
        if !previewForceShowNotch {
            guard settings.glowEnabled, !isAsleep else {
                window.orderOut(nil)
                return
            }
        }
        window.updateFrame()
        apply()
        window.orderFront(nil)
    }

    @objc func apply() {
        if !previewForceShowNotch {
            guard settings.glowEnabled, !isAsleep else {
                window.orderOut(nil)
                return
            }
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let displayState = previewState ?? currentState

        guard let appearance = displayState.appearance(using: settings) else {
            window.orderOut(nil)
            return
        }

        // reduceMotion 或低电量模式下，所有动态效果降级为静态。
        let motionEnabled = !reduceMotion && !lowPower
        let animationMode: StateAppearance.AnimationMode = motionEnabled ? appearance.mode : .steady

        logger.debug("apply state=\(String(describing: displayState)) preview=\(String(describing: self.previewState)) reduceMotion=\(reduceMotion) lowPower=\(lowPower)")
        window.apply(
            settings: settings,
            color: appearance.color,
            animationMode: animationMode
        )
        window.orderFront(nil)
    }
}
