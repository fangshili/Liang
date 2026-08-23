// OnboardingView.swift
// Liang v2 onboarding (SwiftUI) — two-step guide.
//
// Step 1: Connect a Coding Agent (Cursor setup).
// Step 2: Choose glows — hover each card to preview the real effect live.

import SwiftUI
import AppKit

// MARK: - Preview state model

enum GlowPreviewState: Equatable {
    case idle
    case processing
    case success

    var accentColor: Color {
        switch self {
        case .idle:       return Color(red: 1.0, green: 0.57, blue: 0.16)
        case .processing: return Color(red: 0.35, green: 0.62, blue: 0.95)
        case .success:    return Color(red: 0.41, green: 0.84, blue: 0.42)
        }
    }

    var badgeLabel: String {
        switch self {
        case .idle:       return I18n.shared.string(.onboardingStateBadgeIdle)
        case .processing: return I18n.shared.string(.onboardingStateBadgeProcessing)
        case .success:    return I18n.shared.string(.onboardingStateBadgeSuccess)
        }
    }
}

// MARK: - Root

struct OnboardingRootView: View {
    @EnvironmentObject var settings: GlowSettings
    @ObservedObject private var cursorSetup = CursorSetupManager.shared
    @ObservedObject private var coordinator = OnboardingFlowCoordinator.shared

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.085)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if coordinator.currentStep == 1 {
                        OnboardingStep1View()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    } else {
                        OnboardingStep2View()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 560)
        .animation(.easeInOut(duration: 0.35), value: coordinator.currentStep)
        .onAppear { handleInitialEntry() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { n in
            if let w = n.object as? NSWindow,
               w.windowController is OnboardingWindowController {
                OnboardingGlowPreviewManager.shared.stopPreview()
            }
        }
    }

    // MARK: - Actions

    private func handleInitialEntry() {
        if coordinator.currentStep == 2 { return }
        cursorSetup.refresh()
    }
}

// MARK: - Step 1: Connect a Coding Agent

private enum Step1Alert: Identifiable {
    case installConfirmation
    case cursorNotInstalled
    case claudeInstallConfirmation
    case claudeNotInstalled
    case codexInstallConfirmation
    case codexNotInstalled

    var id: String {
        switch self {
        case .installConfirmation: return "install"
        case .cursorNotInstalled: return "no-cursor"
        case .claudeInstallConfirmation: return "claude-install"
        case .claudeNotInstalled: return "no-claude"
        case .codexInstallConfirmation: return "codex-install"
        case .codexNotInstalled: return "no-codex"
        }
    }
}

struct OnboardingStep1View: View {
    @State private var activeAlert: Step1Alert?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(I18n.shared.string(.onboardingConnectorTitle))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text(I18n.shared.string(.onboardingConnectorSubtitle))
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .padding(.top, 40)
            .padding(.bottom, 28)

            // Cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    CursorHeroCard(
                        onRequestInstall: { activeAlert = .installConfirmation },
                        onCursorNotInstalled: { activeAlert = .cursorNotInstalled }
                    )
                    .frame(maxWidth: 560)

                    ClaudeHeroCard(
                        onRequestInstall: { activeAlert = .claudeInstallConfirmation },
                        onClaudeNotInstalled: { activeAlert = .claudeNotInstalled }
                    )
                    .frame(maxWidth: 560)

                    CodexHeroCard(
                        onRequestInstall: { activeAlert = .codexInstallConfirmation },
                        onCodexNotInstalled: { activeAlert = .codexNotInstalled }
                    )
                    .frame(maxWidth: 560)

                    OtherAgentsCard()
                        .frame(maxWidth: 560)
                }
                .padding(.horizontal, 40)
            }

            // Footer
            Step1Footer()
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .installConfirmation:
                return Alert(
                    title: Text(I18n.shared.string(.installConfirmTitle)),
                    message: Text(I18n.shared.string(.installConfirmMessage)),
                    primaryButton: .cancel(Text(I18n.shared.string(.cancel))),
                    secondaryButton: .default(Text(I18n.shared.string(.autoInstall))) {
                        CursorSetupManager.shared.installAutomatically()
                    }
                )
            case .cursorNotInstalled:
                return Alert(
                    title: Text(I18n.shared.string(.onboardingCursorNotInstalledTitle)),
                    message: Text(I18n.shared.string(.onboardingCursorNotInstalledMessage)),
                    primaryButton: .default(Text(I18n.shared.string(.onboardingCursorNotInstalledContinue))),
                    secondaryButton: .default(Text(I18n.shared.string(.onboardingCursorNotInstalledDownload))) {
                        if let url = URL(string: "https://cursor.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            case .claudeInstallConfirmation:
                return Alert(
                    title: Text(I18n.shared.string(.installConfirmTitle)),
                    message: Text(I18n.shared.string(.claudeInstallConfirmMessage)),
                    primaryButton: .cancel(Text(I18n.shared.string(.cancel))),
                    secondaryButton: .default(Text(I18n.shared.string(.autoInstall))) {
                        ClaudeCodeSetupManager.shared.installAutomatically()
                    }
                )
            case .claudeNotInstalled:
                return Alert(
                    title: Text(I18n.shared.string(.onboardingClaudeNotInstalledTitle)),
                    message: Text(I18n.shared.string(.onboardingClaudeNotInstalledMessage)),
                    primaryButton: .default(Text(I18n.shared.string(.onboardingCursorNotInstalledContinue))),
                    secondaryButton: .default(Text(I18n.shared.string(.onboardingClaudeNotInstalledDownload))) {
                        if let url = URL(string: "https://code.claude.com/docs/en/setup") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            case .codexInstallConfirmation:
                return Alert(
                    title: Text(I18n.shared.string(.installConfirmTitle)),
                    message: Text(I18n.shared.string(.codexInstallConfirmMessage)),
                    primaryButton: .cancel(Text(I18n.shared.string(.cancel))),
                    secondaryButton: .default(Text(I18n.shared.string(.autoInstall))) {
                        CodexSetupManager.shared.installAutomatically()
                    }
                )
            case .codexNotInstalled:
                return Alert(
                    title: Text(I18n.shared.string(.onboardingCodexNotInstalledTitle)),
                    message: Text(I18n.shared.string(.onboardingCodexNotInstalledMessage)),
                    primaryButton: .default(Text(I18n.shared.string(.onboardingCursorNotInstalledContinue))),
                    secondaryButton: .default(Text(I18n.shared.string(.onboardingCodexNotInstalledDownload))) {
                        if let url = URL(string: "https://github.com/openai/codex") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
        }
    }
}

private struct Step1Footer: View {
    var body: some View {
        HStack {
            Spacer()
            OnboardingButton(
                title: I18n.shared.string(.onboardingNext),
                style: .primary,
                action: { OnboardingFlowCoordinator.shared.advanceToStep2() }
            )
        }
    }
}

// MARK: - Cursor Hero Card

struct CursorHeroCard: View {
    @ObservedObject private var manager = CursorSetupManager.shared

    let onRequestInstall: () -> Void
    let onCursorNotInstalled: () -> Void

    private var isConfigured: Bool { manager.status.isConfigured }

    private var statusIcon: String {
        isConfigured ? "checkmark.circle.fill" : "circle"
    }

    private var statusColor: Color {
        isConfigured ? Color(red: 0.41, green: 0.84, blue: 0.42) : Color.white.opacity(0.35)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            IDEImageIcon(ide: .cursor, color: .white)
                .frame(width: 38, height: 38)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(I18n.shared.string(.onboardingCursorCardTitle))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(I18n.shared.string(.onboardingCursorCardDesc))
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(2)
            }

            Spacer()

            // Status + action
            VStack(alignment: .trailing, spacing: 8) {
                if isConfigured {
                    HStack(spacing: 5) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(statusColor)
                        Text(I18n.shared.string(.onboardingCursorConnected))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                } else {
                    OnboardingButton(
                        title: I18n.shared.string(.configure),
                        style: .primary,
                        size: .small,
                        action: handleConfigure
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func handleConfigure() {
        if manager.isCursorInstalled {
            onRequestInstall()
        } else {
            onCursorNotInstalled()
        }
    }
}

// MARK: - Claude Code Hero Card

struct ClaudeHeroCard: View {
    @ObservedObject private var manager = ClaudeCodeSetupManager.shared

    let onRequestInstall: () -> Void
    let onClaudeNotInstalled: () -> Void

    private var isConfigured: Bool { manager.status.isConfigured }

    private var statusIcon: String {
        isConfigured ? "checkmark.circle.fill" : "circle"
    }

    private var statusColor: Color {
        isConfigured ? Color(red: 0.41, green: 0.84, blue: 0.42) : Color.white.opacity(0.35)
    }

    private var claudeOrange: Color {
        Color(red: 0.84, green: 0.47, blue: 0.32)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            IDEImageIcon(ide: .claudeCode, color: claudeOrange)
                .frame(width: 38, height: 38)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(I18n.shared.string(.claudeCode))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(I18n.shared.string(.onboardingClaudeCardDesc))
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(2)
            }

            Spacer()

            // Status + action
            VStack(alignment: .trailing, spacing: 8) {
                if isConfigured {
                    HStack(spacing: 5) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(statusColor)
                        Text(I18n.shared.string(.onboardingCursorConnected))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                } else {
                    OnboardingButton(
                        title: I18n.shared.string(.configure),
                        style: .primary,
                        size: .small,
                        action: handleConfigure
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func handleConfigure() {
        if manager.isClaudeCodeInstalled {
            onRequestInstall()
        } else {
            onClaudeNotInstalled()
        }
    }
}

// MARK: - Codex Hero Card

struct CodexHeroCard: View {
    @ObservedObject private var manager = CodexSetupManager.shared

    let onRequestInstall: () -> Void
    let onCodexNotInstalled: () -> Void

    private var isConfigured: Bool { manager.status.isConfigured }

    private var statusIcon: String {
        isConfigured ? "checkmark.circle.fill" : "circle"
    }

    private var statusColor: Color {
        isConfigured ? Color(red: 0.41, green: 0.84, blue: 0.42) : Color.white.opacity(0.35)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            IDEImageIcon(ide: .codex, color: .white)
                .frame(width: 38, height: 38)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(I18n.shared.string(.codex))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(I18n.shared.string(.onboardingCodexCardDesc))
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(3)
            }

            Spacer()

            // Status + action
            VStack(alignment: .trailing, spacing: 8) {
                if isConfigured {
                    HStack(spacing: 5) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(statusColor)
                        Text(I18n.shared.string(.onboardingCursorConnected))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                } else {
                    OnboardingButton(
                        title: I18n.shared.string(.configure),
                        style: .primary,
                        size: .small,
                        action: handleConfigure
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func handleConfigure() {
        if manager.isCodexInstalled {
            onRequestInstall()
        } else {
            onCodexNotInstalled()
        }
    }
}

/// 从 IDE 图标资源加载的 SwiftUI 视图：template 图标按 color 着色，彩色图标原样显示。
private struct IDEImageIcon: View {
    let ide: IDE
    let color: Color

    var body: some View {
        if let image = ide.onboardingIconImage {
            if image.isTemplate {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(color)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

// MARK: - Other Agents Card

private struct OtherAgentsCard: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(I18n.shared.string(.onboardingOtherAgentsTitle))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            Text(I18n.shared.string(.onboardingOtherAgentsHint))
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(I18n.shared.string(.onboardingOtherComingSoon))
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Step 2: Choose your glow

struct OnboardingStep2View: View {
    @EnvironmentObject var settings: GlowSettings

    private var notchAvailable: Bool {
        DeviceCapability.hasNotchedScreen
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(I18n.shared.string(.onboardingGlowTitle))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text(I18n.shared.string(.onboardingGlowSubtitle))
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            // Glow cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Notch (only on notched Macs)
                    if notchAvailable {
                        GlowPreviewCard(
                            title: I18n.shared.string(.onboardingNotchCardTitle),
                            description: I18n.shared.string(.onboardingNotchCardDesc),
                            bindingEnabled: $settings.glowEnabled,
                            enabled: true,
                            disableReason: nil,
                            previewTarget: .notch,
                            staticPreview: { isHovered in NotchStaticPreview(isHovered: isHovered) }
                        )
                        .frame(maxWidth: 560)
                    }

                    // Cursor
                    GlowPreviewCard(
                        title: I18n.shared.string(.onboardingCursorGlowCardTitle),
                        description: I18n.shared.string(.onboardingCursorGlowCardDesc),
                        bindingEnabled: $settings.cursorGlowEnabled,
                        enabled: true,
                        disableReason: nil,
                        previewTarget: .cursor,
                        staticPreview: { isHovered in CursorStaticPreview(isHovered: isHovered) }
                    )
                    .frame(maxWidth: 560)

                    // Menu Bar
                    GlowPreviewCard(
                        title: I18n.shared.string(.onboardingMenuBarCardTitle),
                        description: I18n.shared.string(.onboardingMenuBarCardDesc),
                        bindingEnabled: $settings.menuBarStateColorEnabled,
                        enabled: true,
                        disableReason: nil,
                        previewTarget: .menuBar,
                        staticPreview: { isHovered in MenuBarStaticPreview(isHovered: isHovered) }
                    )
                    .frame(maxWidth: 560)
                }
                .padding(.horizontal, 40)
            }

            // Footer
            HStack {
                OnboardingButton(
                    title: "←  " + I18n.shared.string(.onboardingBack),
                    style: .ghost,
                    action: { OnboardingFlowCoordinator.shared.advanceToStep1() }
                )
                Spacer()
                OnboardingButton(
                    title: I18n.shared.string(.onboardingSetupLater),
                    style: .ghost,
                    action: {
                        GlowSettings.shared.hasCompletedOnboarding = true
                        OnboardingFlowCoordinator.shared.complete()
                    }
                )
                OnboardingButton(
                    title: I18n.shared.string(.onboardingStartUsing),
                    style: .primary,
                    action: { OnboardingFlowCoordinator.shared.complete() }
                )
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Glow Preview Card (hover-to-preview)

struct GlowPreviewCard<Preview: View>: View {
    let title: String
    let description: String
    @Binding var bindingEnabled: Bool
    let enabled: Bool
    let disableReason: String?
    let previewTarget: OnboardingGlowPreviewManager.PreviewTarget
    @ViewBuilder let staticPreview: (Bool) -> Preview

    @State private var isHoveringPreview: Bool = false
    @ObservedObject private var previewManager = OnboardingGlowPreviewManager.shared
    @ObservedObject private var coordinator = OnboardingFlowCoordinator.shared

    private let previewBlue = Color(red: 0.30, green: 0.62, blue: 0.95)

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Preview area — static, with hover border + live glow
            ZStack(alignment: .bottomTrailing) {
                staticPreview(isHoveringPreview)
                    .frame(width: 200, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Border overlay
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isHoveringPreview && enabled
                            ? previewBlue.opacity(0.85)
                            : Color.white.opacity(enabled ? 0.18 : 0.08),
                        lineWidth: isHoveringPreview && enabled ? 2.5 : 1
                    )

                // Hover badge
                if isHoveringPreview {
                    if enabled {
                        Text(I18n.shared.string(.onboardingPreviewActive))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(previewBlue.opacity(0.35))
                            )
                            .padding(6)
                    } else if let reason = disableReason {
                        Text(reason)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.75))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color.white.opacity(0.12))
                            )
                            .padding(6)
                    }
                }
            }
            .frame(width: 200)

            // Info column
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $bindingEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!enabled)
                        .scaleEffect(0.7)
                        .frame(width: 36, height: 20)
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !enabled, let reason = disableReason {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(reason)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Color.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 👆 整个卡片（缩略图 + 信息列）都是悬停热区
        .onHover { hovering in
            guard coordinator.currentStep == 2 else { return }
            if hovering {
                isHoveringPreview = true
                if enabled {
                    previewManager.startPreview(target: previewTarget)
                }
            } else {
                isHoveringPreview = false
                previewManager.stopPreview()
            }
        }
        .onDisappear {
            if isHoveringPreview {
                previewManager.stopPreview()
            }
            isHoveringPreview = false
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .opacity(enabled ? 1.0 : 0.55)
    }
}

// MARK: - Static Preview Shapes (no animation)

/// 取当前预览状态对应的颜色（用于悬停时把静态图点亮）。
private func currentPreviewColor() -> Color {
    let state = GlowController.shared.previewState ?? .processing
    let nsColor = GlowSettings.shared.stateColors[state]
        ?? StateAppearance.defaultColors[state]
        ?? NSColor.systemOrange
    return Color(nsColor: nsColor)
}

struct NotchStaticPreview: View {
    var isHovered: Bool = false

    private var glowColor: Color { currentPreviewColor() }

    var body: some View {
        ZStack {
            // MacBook lid background
            Color(red: 0.045, green: 0.045, blue: 0.055)

            VStack(spacing: 0) {
                // Bezel top strip with notch
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                        .frame(height: 30)

                    // Notch cutout (as filled shape on dark bezel)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 58, height: 13)
                        .offset(y: 2)

                    // 紧贴刘海外缘的细光晕
                    if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(glowColor, lineWidth: 1.4)
                            .frame(width: 66, height: 19)
                            .offset(y: -1)
                            .shadow(color: glowColor.opacity(0.45), radius: 3, x: 0, y: 0)
                    }
                }

                // Screen area
                Rectangle()
                    .fill(Color(red: 0.025, green: 0.025, blue: 0.035))
                    .overlay(
                        VStack(spacing: 8) {
                            shimmerLine(width: 110)
                            shimmerLine(width: 85)
                            shimmerLine(width: 140)
                        }
                        .padding(.top, 18)
                    )
            }
        }
    }

    private func shimmerLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .frame(width: width, height: 5)
    }
}

struct CursorStaticPreview: View {
    var isHovered: Bool = false

    private var glowColor: Color { currentPreviewColor() }

    var body: some View {
        ZStack {
            // Editor background
            Color(red: 0.035, green: 0.035, blue: 0.045)

            // Code lines
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<7, id: \.self) { i in
                    HStack(spacing: 5) {
                        if i == 4 {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color(red: 0.65, green: 0.55, blue: 0.95))
                                .frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.white.opacity(0.13))
                                .frame(width: CGFloat([70, 95, 60, 120, 55, 85, 105][i]), height: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .frame(width: CGFloat([70, 95, 60, 120, 55, 85, 105][i]), height: 4)
                        }
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Cursor arrow + tiny lower-right glow
            ZStack {
                // Tight diffused aura, shifted further down-right
                if isHovered {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [glowColor.opacity(0.45), glowColor.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 11
                            )
                        )
                        .frame(width: 22, height: 18)
                        .offset(x: 10, y: 14)
                        .blur(radius: 1.2)
                }

                CursorArrowShape()
                    .fill(isHovered ? Color.white.opacity(0.95) : Color.white.opacity(0.8))
                    .frame(width: 13, height: 17)
            }
            .offset(x: 28, y: 22)
        }
    }
}

struct MenuBarStaticPreview: View {
    var isHovered: Bool = false

    private var orbColor: Color { isHovered ? currentPreviewColor() : Color.white.opacity(0.85) }

    var body: some View {
        ZStack(alignment: .top) {
            // Screen content (below menu bar)
            Color(red: 0.035, green: 0.035, blue: 0.045)

            VStack(spacing: 0) {
                // Menu bar strip
                HStack(spacing: 0) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(.horizontal, 6)

                    ForEach(["File", "Edit", "View"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))
                            .padding(.horizontal, 6)
                    }

                    Spacer()

                    // Wifi + battery + Liang orb icons
                    Image(systemName: "wifi")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.55))

                    Image(systemName: "battery.75")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.55))
                        .padding(.trailing, 2)

                    // Liang orb placed directly inside the menu bar, left of its trailing edge
                    ZStack {
                        if isHovered {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [orbColor.opacity(0.45), orbColor.opacity(0)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 8
                                    )
                                )
                                .frame(width: 16, height: 16)
                                .blur(radius: 1.2)
                        }

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [orbColor.opacity(0.75), orbColor.opacity(0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 5
                                )
                            )
                            .frame(width: 10, height: 10)
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 22)
                .background(Color(red: 0.075, green: 0.075, blue: 0.085))

                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)

                Spacer()
            }
        }
    }
}

// MARK: - Shapes

struct CursorArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.85, y: h))
        path.addLine(to: CGPoint(x: w, y: h * 0.8))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.25))
        path.closeSubpath()
        return path
    }
}

struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 8
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct PulseDot: View {
    let color: Color
    let isActive: Bool

    @State private var scale: CGFloat = 0.8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .onAppear {
                if isActive {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        scale = 1.3
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: newValue)) {
                    scale = newValue ? 1.3 : 0.8
                }
            }
    }
}

// MARK: - Thanks Sheet

struct ThanksView: View {
    @EnvironmentObject var i18n: I18n
    let onClose: () -> Void

    private var thanksBody: String {
        i18n.string(.onboardingThanksBody).replacingOccurrences(of: "\\n", with: "\n")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(i18n.string(.onboardingThanksTitle))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)

            Text(thanksBody)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            OnboardingButton(
                title: i18n.string(.onboardingThanksClose),
                style: .primary,
                action: onClose
            )
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Onboarding Button

enum OnboardingButtonStyle {
    case primary
    case ghost
}

enum OnboardingButtonSize {
    case normal
    case small
}

struct OnboardingButton: View {
    let title: String
    let style: OnboardingButtonStyle
    var size: OnboardingButtonSize = .normal
    let action: () -> Void

    // Blue primary — matches prototype
    private let primaryBlueTop    = Color(red: 0.35, green: 0.62, blue: 0.95)
    private let primaryBlueBottom = Color(red: 0.20, green: 0.45, blue: 0.85)

    private var fontSize: CGFloat { size == .small ? 11 : 13 }
    private var vPadding: CGFloat { size == .small ? 5 : 7 }
    private var hPadding: CGFloat { size == .small ? 12 : 18 }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(foregroundColor)
                .padding(.horizontal, hPadding)
                .padding(.vertical, vPadding)
                .background(backgroundView)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .ghost:   return Color.white.opacity(0.6)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [primaryBlueTop, primaryBlueBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: primaryBlueTop.opacity(0.35), radius: 6, y: 2)

        case .ghost:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
    }
}
