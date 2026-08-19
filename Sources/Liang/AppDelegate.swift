import AppKit
import os
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.liang", category: "AppDelegate")

    /// Token returned by `ProcessInfo.beginActivity(options:reason:)` to keep the
    /// menu-bar-only app alive across sleep/wake cycles and reduce the chance of
    /// App Nap / sudden termination.
    private var activityToken: NSObjectProtocol?

        /// Sparkle 自动更新控制器。`startingUpdater: true` 会在应用启动后按 appcast 自动检查更新。
    /// 通过静态属性暴露，避免 SwiftUI App 生命周期中 `NSApp.delegate` 不是 `AppDelegate` 实例导致拿不到 updater。
    static private(set) var sharedUpdaterController: SPUStandardUpdaterController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.log.info("applicationDidFinishLaunching")

        // Initialize Sparkle before other UI so the "Check for Updates" menu item has a target.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        Self.sharedUpdaterController = controller

        // Keep the app responsive when running as a background agent.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Liang menu-bar helper needs to stay alive to receive IDE events and render glow"
        )

        // Force the shared instance to load its defaults.
        _ = GlowSettings.shared

        // Apply device-specific defaults for first-run users.
        applyDeviceDefaultsIfNeeded()

        StatusBarController.shared.start()
        GlowController.shared.start()
        CursorGlowController.shared.start()
        StateEngine.shared.start()

        // Observe sleep/wake so we can reconnect the file watcher, whose file
        // descriptor may become stale after the Mac sleeps.
        registerSleepWakeObservers()

        // Show onboarding if the user has never completed it.
        if !GlowSettings.shared.hasCompletedOnboarding {
            Self.log.info("First launch detected — showing onboarding window")
            // 在 onboarding 完成前，强制关闭所有光晕效果，避免新用户被未预期的
            // 刘海/光标/菜单栏光晕干扰；用户可在 Step 2 中自行开启。
            GlowSettings.shared.glowEnabled = false
            GlowSettings.shared.cursorGlowEnabled = false
            GlowSettings.shared.menuBarStateColorEnabled = false
            OnboardingWindowController.shared.windowDidLoad()
            OnboardingWindowController.shared.show()
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    /// Apply device-specific default settings for fresh installs.
    @MainActor
    private func applyDeviceDefaultsIfNeeded() {
        let settings = GlowSettings.shared

        // First-run detection: only apply defaults if the user has no stored settings yet.
        // The `defaults` stored under "com.liang.settings.v1" is the canonical check.
        let key = "com.liang.settings.v1"
        guard UserDefaults.standard.data(forKey: key) == nil else { return }

        if DeviceCapability.hasNotchedScreen {
            // 有刘海：默认开启刘海光晕，关闭光标/菜单栏状态色
            settings.glowEnabled = true
            settings.cursorGlowEnabled = false
            settings.menuBarStateColorEnabled = false
        } else {
            // 无刘海：关闭刘海/光标光晕，开启菜单栏状态色作为默认反馈
            settings.glowEnabled = false
            settings.cursorGlowEnabled = false
            settings.menuBarStateColorEnabled = true
        }
    }

    @MainActor
    private func registerSleepWakeObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @MainActor
    @objc private func systemWillSleep(_ notification: Notification) {
        Self.log.info("System will sleep — pausing glow")
        // Existing controllers already listen to these notifications, but we also
        // stop the adapters to avoid using a stale file descriptor during sleep.
        StateEngine.shared.pauseAllAdapters()
    }

    @MainActor
    @objc private func systemDidWake(_ notification: Notification) {
        Self.log.info("System did wake — restoring services")
        // Reconnect the IDE adapters and ask all glow controllers to refresh.
        StateEngine.shared.resumeAllAdapters()
        GlowController.shared.apply()
        CursorGlowController.shared.apply()
        StatusBarController.shared.refreshMenuBarIcon()
    }

    @MainActor
    @objc private func screenParametersChanged(_ notification: Notification) {
        Self.log.info("Screen parameters changed — refreshing glow geometry")
        GlowController.shared.apply()
        CursorGlowController.shared.apply()
    }
}
