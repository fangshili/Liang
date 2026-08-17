// OnboardingGlowPreviewManager.swift
// Coordinates hover-triggered real glow previews in the onboarding Step 2 cards.
// 仅展示效果，**不会**改写用户的 glowEnabled / cursorGlowEnabled / menuBarStateColorEnabled
// 设置；通过对应 controller / renderer 的 previewForceShow* 标志临时强制显示。

import Foundation
import Combine
import os

@MainActor
final class OnboardingGlowPreviewManager: ObservableObject {
    static let shared = OnboardingGlowPreviewManager()

    enum PreviewTarget {
        case notch
        case cursor
        case menuBar
    }

    @Published private(set) var activeTarget: PreviewTarget? = nil
    @Published private(set) var isPreviewing: Bool = false

    private var timer: Timer?
    private let stateCycle: [LiangState] = [.processing, .success, .idle]
    private var cycleIndex: Int = 0

    private static let log = Logger(subsystem: "com.liang", category: "OnboardingPreview")

    private init() {}

    /// 开始预览。重复调用同一目标会重启循环；切换到别的目标会先停止旧的。
    func startPreview(target: PreviewTarget) {
        if isPreviewing && activeTarget == target { return }
        stopPreview()

        activeTarget = target
        isPreviewing = true
        cycleIndex = 0

        // 只设置 force-show 标志，不改写用户设置。
        switch target {
        case .notch:
            GlowController.shared.previewForceShowNotch = true
        case .cursor:
            CursorGlowController.shared.previewForceShow = true
        case .menuBar:
            StatusBarIconRenderer.previewForceShowMenuBarColor = true
            StatusBarController.shared.refreshMenuBarIcon()
        }

        GlowController.shared.previewState = stateCycle[0]
        Self.log.info("Preview started for \(String(describing: target))")

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceCycle() }
        }
    }

    /// 结束预览：清空所有 force-show 标志；用户原本的开关状态保持不变。
    func stopPreview() {
        guard isPreviewing else { return }
        timer?.invalidate()
        timer = nil

        GlowController.shared.previewState = nil
        GlowController.shared.previewForceShowNotch = false
        CursorGlowController.shared.previewForceShow = false
        StatusBarIconRenderer.previewForceShowMenuBarColor = false
        StatusBarController.shared.refreshMenuBarIcon()

        activeTarget = nil
        isPreviewing = false
        Self.log.info("Preview stopped")
    }

    private func advanceCycle() {
        guard isPreviewing else { return }
        cycleIndex = (cycleIndex + 1) % stateCycle.count
        GlowController.shared.previewState = stateCycle[cycleIndex]
    }
}
