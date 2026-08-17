import AppKit
import SwiftUI
import Combine
import Sparkle

final class StatusBarController: NSObject {
    static let shared = StatusBarController()
    private let settings = GlowSettings.shared
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?

    private var statusMenuItem: NSMenuItem?
    private var eventMenuItem: NSMenuItem?
    private var clearErrorItem: NSMenuItem?

    private var currentState: LiangState = .idle

    private override init() {}

    deinit {
        animationTimer?.invalidate()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }

        updateIcon()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown

        startAnimationTimer()

        let menu = NSMenu(title: "Liang")

        let statusItem = NSMenuItem(title: I18n.shared.string(.statusFormat, LiangState.idle.localizedName), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        self.statusMenuItem = statusItem
        menu.addItem(statusItem)

        let eventItem = NSMenuItem(title: I18n.shared.string(.recentEventNone), action: nil, keyEquivalent: "")
        eventItem.isEnabled = false
        self.eventMenuItem = eventItem
        menu.addItem(eventItem)

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: I18n.shared.string(.clearError), action: #selector(clearError), keyEquivalent: "")
        clearItem.target = self
        clearItem.isHidden = true
        self.clearErrorItem = clearItem
        menu.addItem(clearItem)

        let settingsItem = NSMenuItem(title: I18n.shared.string(.settings), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Sparkle "Check for Updates" menu item.
        // 使用 AppDelegate 的静态属性获取 updater。SwiftUI `@NSApplicationDelegateAdaptor`
        // 不保证 `NSApp.delegate` 就是 AppDelegate 实例，所以不再通过它反查。
        let updateItem: NSMenuItem
        if let updaterController = AppDelegate.sharedUpdaterController {
            updateItem = NSMenuItem(
                title: I18n.shared.string(.checkForUpdates),
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            updateItem.target = updaterController
        } else {
            updateItem = NSMenuItem(
                title: I18n.shared.string(.checkForUpdates),
                action: nil,
                keyEquivalent: ""
            )
            updateItem.isEnabled = false
        }
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: I18n.shared.string(.quitApp), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu

        observeStateEngine()
        observeLanguageChanges()
    }

    private func observeStateEngine() {
        let engine = StateEngine.shared

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.currentState = state
                self?.statusMenuItem?.title = I18n.shared.string(.statusFormat, state.localizedName)
                self?.clearErrorItem?.isHidden = state != .error
                self?.updateIcon()
            }
            .store(in: &cancellables)

        engine.$lastEvent
            .combineLatest(engine.$lastEventAt)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event, timestamp in
                guard let event = event else {
                    self?.eventMenuItem?.title = I18n.shared.string(.recentEventNone)
                    return
                }
                let hookName = event.hook
                let timeString = self?.format(timestamp) ?? ""
                self?.eventMenuItem?.title = I18n.shared.string(.recentEventFormat, hookName, timeString)
            }
            .store(in: &cancellables)

        settings.$menuBarStateColorEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        settings.$stateColors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        settings.$stateGlowEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        settings.$breathingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        settings.$breathingSpeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        settings.$menuBarBreathingSpeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        GlowController.shared.previewStateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func observeLanguageChanges() {
        I18n.shared.$currentLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let engine = StateEngine.shared
                self.statusMenuItem?.title = I18n.shared.string(.statusFormat, self.currentState.localizedName)
                if let event = engine.lastEvent, let timestamp = engine.lastEventAt {
                    self.eventMenuItem?.title = I18n.shared.string(.recentEventFormat, event.hook, self.format(timestamp))
                } else {
                    self.eventMenuItem?.title = I18n.shared.string(.recentEventNone)
                }
                self.clearErrorItem?.title = I18n.shared.string(.clearError)
                if let settingsItem = self.statusItem?.menu?.items.first(where: { $0.action == #selector(self.showSettings) }) {
                    settingsItem.title = I18n.shared.string(.settings)
                }
                if let updateItem = self.statusItem?.menu?.items.first(where: { $0.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)) }) {
                    updateItem.title = I18n.shared.string(.checkForUpdates)
                }
                if let quitItem = self.statusItem?.menu?.items.first(where: { $0.action == #selector(self.quit) }) {
                    quitItem.title = I18n.shared.string(.quitApp)
                }
            }
            .store(in: &cancellables)
    }

    private func startAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let displayState = GlowController.shared.previewState ?? currentState
        let intensity = StatusBarIconRenderer.intensity(for: displayState, settings: settings)
        button.image = StatusBarIconRenderer.render(state: displayState, settings: settings, intensity: intensity)
    }

    /// 供 onboarding 预览等场景主动重绘菜单栏图标（例如切换 `previewForceShowMenuBarColor` 后）。
    func refreshMenuBarIcon() {
        updateIcon()
    }

    private func format(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @objc private func clearError() {
        StateEngine.shared.clearError()
    }

    @objc private func showSettings() {
        let screen = statusItem?.button?.window?.screen
        SettingsWindowController.shared.show(on: screen)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
