import SwiftUI
import AppKit
import Combine

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var closeObserver: Any?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = I18n.shared.string(.settingsWindowTitle)
        window.minSize = NSSize(width: 840, height: 530)
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: GlowController.shared.settings))
        window.isReleasedWhenClosed = false
        super.init(window: window)

        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.settingsWindowWillClose()
        }

        I18n.shared.$currentLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak window] _ in
                window?.title = I18n.shared.string(.settingsWindowTitle)
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func settingsWindowWillClose() {
        GlowController.shared.previewState = nil
        GlowController.shared.apply()
    }

    func show(on screen: NSScreen? = nil) {
        guard let window = window else { return }

        let targetScreen = screen ?? window.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let screen = targetScreen {
            let visibleFrame = screen.visibleFrame
            let size = window.frame.size
            let origin = NSPoint(
                x: visibleFrame.origin.x + (visibleFrame.width - size.width) / 2,
                y: visibleFrame.origin.y + (visibleFrame.height - size.height) / 2
            )
            window.setFrameOrigin(origin)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
