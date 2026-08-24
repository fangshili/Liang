// OnboardingWindowController.swift
// Hosts the two-step SwiftUI onboarding flow.

import AppKit
import SwiftUI
import os

@MainActor
final class OnboardingWindowController: NSWindowController {
    static let shared = OnboardingWindowController()

    private static let log = Logger(subsystem: "com.liang", category: "Onboarding")


    /// Current hosting view.
    private var content: NSView?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Liang"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard self.window != nil else { return }

        let initialStep = preferredInitialStep()
        OnboardingFlowCoordinator.shared.currentStep = initialStep
        installContent()
        OnboardingFlowCoordinator.shared.host = self
        Self.log.info("OnboardingWindowController windowDidLoad, step=\(initialStep, privacy: .public)")
    }

    func show() {
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Step transition triggered from SwiftUI buttons.
    /// The coordinator's `@Published currentStep` drives SwiftUI state; no view rebuild needed.
    func advance(to step: Int) {
        guard (1...2).contains(step) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            OnboardingFlowCoordinator.shared.currentStep = step
        }
        Self.log.info("OnboardingWindowController advance to step \(step, privacy: .public)")
    }

    /// User finished the flow. Persist completion, dismiss onboarding window,
    /// then show a small "thanks" sheet with a single close button.
    func complete() {
        GlowSettings.shared.hasCompletedOnboarding = true
        if case .configured = CursorSetupManager.shared.status {
            GlowSettings.shared.hasCompletedCursorSetup = true
        }
        if case .configured = ClaudeCodeSetupManager.shared.status {
            GlowSettings.shared.hasCompletedClaudeSetup = true
        }
        if case .configured = CodexSetupManager.shared.status {
            GlowSettings.shared.hasCompletedCodexSetup = true
        }
        if case .configured = CodeBuddySetupManager.shared.status {
            GlowSettings.shared.hasCompletedCodeBuddySetup = true
        }
        Self.log.info("OnboardingWindowController complete()")

        guard let window = self.window else { return }
        close()

        DispatchQueue.main.async { [weak self] in
            self?.showThanksSheet(parentedTo: window)
        }
    }

    private func showThanksSheet(parentedTo onboardingWindow: NSWindow) {
        let thanksWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        thanksWindow.title = ""
        thanksWindow.titlebarAppearsTransparent = true
        thanksWindow.titleVisibility = .hidden
        thanksWindow.appearance = NSAppearance(named: .darkAqua)
        thanksWindow.isReleasedWhenClosed = false
        thanksWindow.center()

        let root = ThanksView { [weak thanksWindow] in
            thanksWindow?.close()
        }
        .environmentObject(I18n.shared)

        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        thanksWindow.contentView = host
        thanksWindow.setContentSize(NSSize(width: 420, height: 220))

        // Position centered over the onboarding window so the transition feels
        // anchored, even though the onboarding window has been closed.
        if let screenFrame = onboardingWindow.screen?.frame ?? NSScreen.main?.frame {
            let thanksSize = NSSize(width: 420, height: 220)
            let onboardingFrame = onboardingWindow.frame
            let originX = onboardingFrame.midX - thanksSize.width / 2
            let originY = onboardingFrame.midY - thanksSize.height / 2
            var origin = NSPoint(x: originX, y: originY)

            // Keep the sheet fully inside the screen bounds.
            origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - thanksSize.width))
            origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - thanksSize.height))
            thanksWindow.setFrameOrigin(origin)
        }

        thanksWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Decide which step to land on first.
    /// T11: 无论 Cursor 桥接状态如何，只要用户还没完成 onboarding，就固定进入 Step 1。
    private func preferredInitialStep() -> Int {
        return GlowSettings.shared.hasCompletedOnboarding ? 2 : 1
    }

    /// Install the SwiftUI hosting view once. Step changes are driven by
    /// `OnboardingFlowCoordinator.currentStep` without rebuilding the view.
    private func installContent() {
        guard let window = self.window else { return }
        let root = OnboardingRootView()
            .environmentObject(GlowSettings.shared)
            .environmentObject(I18n.shared)
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = host
        window.setContentSize(NSSize(width: 760, height: 560))
        self.content = host
    }
}
