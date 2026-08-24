import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: GlowSettings
    @StateObject private var i18n = I18n.shared
    @State private var selectedCategory: SettingsCategory = .codingAgent

    var body: some View {
        let _ = i18n.currentLanguage
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(i18n)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Liang")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ForEach(SettingsCategory.allCases) { category in
                SidebarItem(
                    category: category,
                    isSelected: selectedCategory == category
                ) {
                    selectedCategory = category
                }
            }

            Spacer()
        }
        .frame(width: 180)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(selectedCategory.title)
                    .font(.title2)
                    .fontWeight(.bold)

                detailView(for: selectedCategory)

                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func detailView(for category: SettingsCategory) -> some View {
        switch category {
        case .glow:
            GlowPage(settings: settings)
        case .codingAgent:
            CodingAgentPage(settings: settings)
        case .colors:
            ColorsPage(settings: settings)
        case .advanced:
            AdvancedPage(settings: settings)
        case .about:
            AboutPage()
        }
    }
}

// MARK: - Sidebar

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case codingAgent, colors, glow, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glow: return I18n.shared.string(.glow)
        case .codingAgent: return I18n.shared.string(.codingAgent)
        case .colors: return I18n.shared.string(.stateColors)
        case .advanced: return I18n.shared.string(.advanced)
        case .about: return I18n.shared.string(.about)
        }
    }

    var icon: String {
        switch self {
        case .glow: return "lightbulb"
        case .codingAgent: return "bubble.left.and.bubble.right"
        case .colors: return "paintpalette"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

private struct SidebarItem: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 13))
                    .frame(width: 18, alignment: .center)
                Text(category.title)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
}

// MARK: - Pages

private enum GlowTab: String, CaseIterable, Identifiable {
    case general
    case notch
    case cursor
    case menuBar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return I18n.shared.string(.glowTabGeneral)
        case .notch: return I18n.shared.string(.glowTabNotch)
        case .cursor: return I18n.shared.string(.glowTabCursor)
        case .menuBar: return I18n.shared.string(.glowTabMenuBar)
        }
    }
}

private struct GlowPage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n
    @State private var selectedTab: GlowTab = .general

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 16) {
            Picker(selection: $selectedTab) {
                ForEach(availableTabs) { tab in
                    Text(tab.label).tag(tab)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .fixedSize()

            tabContent
        }
    }

    private var availableTabs: [GlowTab] {
        var tabs = GlowTab.allCases
        if !DeviceCapability.hasNotchedScreen {
            tabs.removeAll { $0 == .notch }
        }
        return tabs
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalContent
        case .notch:
            notchContent
        case .cursor:
            cursorContent
        case .menuBar:
            menuBarContent
        }
    }

    private var generalContent: some View {
        GroupBox(I18n.shared.string(.glowTabGeneral)) {
            VStack(alignment: .leading, spacing: 14) {
                sliderRow(I18n.shared.string(.brightness), value: $settings.brightness, range: 0.1...1, step: 0.05)
                sliderRow(I18n.shared.string(.blurRadius), value: $settings.blurRadius, range: 0...40, step: 0.5)

                HStack {
                    Spacer()
                    Button(I18n.shared.string(.restoreDefaults)) {
                        settings.restoreGeneralGlowDefaults()
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(4)
        }
    }

    private var notchContent: some View {
        GroupBox(I18n.shared.string(.glowTabNotch)) {
            VStack(alignment: .leading, spacing: 14) {
                if let metrics = DeviceCapability.notchMetrics {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(I18n.shared.string(.notchSize) + ": \(Int(metrics.width))×\(Int(metrics.height))pt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                Toggle(I18n.shared.string(.enableNotchGlow), isOn: $settings.glowEnabled)
                    .help(I18n.shared.string(.notchGlowHelp))

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 4) {
                        Toggle(I18n.shared.string(.breathingEnabled), isOn: $settings.breathingEnabled)
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .help(I18n.shared.string(.breathingSettingsHelp))
                        Spacer()
                    }
                    sliderRow(I18n.shared.string(.breathingSpeed), value: $settings.breathingSpeed, range: 0.2...3, step: 0.05)
                        .disabled(!settings.breathingEnabled)
                    sliderRow(I18n.shared.string(.outerThickness), value: $settings.outerThickness, range: 1...12, step: 0.1)
                    sliderRow(I18n.shared.string(.innerThickness), value: $settings.innerThickness, range: 0...8, step: 0.1)
                    sliderRow(I18n.shared.string(.notchInset), value: $settings.notchInset, range: 0...10, step: 0.1)
                    sliderRow(I18n.shared.string(.horizontalOffset), value: $settings.horizontalOffset, range: -5...5, step: 0.1)
                    sliderRow(I18n.shared.string(.cornerRadiusScale), value: $settings.cornerRadiusScale, range: 0.1...1.0, step: 0.02)
                }
                .padding(.top, 2)
                .disabled(!settings.glowEnabled)

                HStack {
                    Spacer()
                    Button(I18n.shared.string(.restoreDefaults)) {
                        settings.restoreNotchDefaults()
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(4)
        }
    }

    private var cursorContent: some View {
        GroupBox(I18n.shared.string(.glowTabCursor)) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(I18n.shared.string(.enableCursorGlow), isOn: $settings.cursorGlowEnabled)
                    .help(I18n.shared.string(.cursorGlowHelp))

                VStack(alignment: .leading, spacing: 14) {
                    sliderRow(I18n.shared.string(.cursorSize), value: $settings.cursorGlowSize, range: 12...64, step: 1)
                    sliderRow(I18n.shared.string(.horizontalOffset), value: $settings.cursorGlowOffsetX, range: -40...40, step: 1)
                    sliderRow(I18n.shared.string(.verticalOffset), value: $settings.cursorGlowOffsetY, range: -40...40, step: 1)
                }
                .padding(.top, 2)
                .disabled(!settings.cursorGlowEnabled)

                HStack {
                    Spacer()
                    Button(I18n.shared.string(.restoreDefaults)) {
                        settings.restoreCursorGlowDefaults()
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(4)
        }
    }

    private var menuBarContent: some View {
        GroupBox(I18n.shared.string(.glowTabMenuBar)) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(I18n.shared.string(.enableMenuBarStateColor), isOn: $settings.menuBarStateColorEnabled)
                    .help(I18n.shared.string(.menuBarStateColorHelp))

                sliderRow(I18n.shared.string(.breathingSpeed), value: $settings.menuBarBreathingSpeed, range: 0.2...2, step: 0.05)
                    .padding(.top, 2)
                    .disabled(!settings.menuBarStateColorEnabled)

                HStack {
                    Spacer()
                    Button(I18n.shared.string(.restoreDefaults)) {
                        settings.restoreMenuBarDefaults()
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(4)
        }
    }
}

private struct CodingAgentPage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n
    @State private var selectedIDE: IDE = .cursor

    @ObservedObject private var cursorManager = CursorSetupManager.shared
    @ObservedObject private var claudeManager = ClaudeCodeSetupManager.shared
    @ObservedObject private var codexManager = CodexSetupManager.shared
    @ObservedObject private var codeBuddyManager = CodeBuddySetupManager.shared

    var body: some View {
        let _ = i18n.currentLanguage
        HStack(spacing: 0) {
            ideList
            Divider()
            detailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            refreshInstallationState()
        }
    }

    private var ideList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(IDE.allCases) { ide in
                ideRow(ide)
            }
            Spacer()
        }
        .frame(width: 200)
        .padding(.top, 8)
        .padding(.horizontal, 12)
    }

    private func ideRow(_ ide: IDE) -> some View {
        let isSelected = selectedIDE == ide
        let isSupported = ide != .trae
        let installed = isIDEInstalled(ide)

        return HStack(spacing: 12) {
            Text(ide.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            if isSupported && !installed {
                Text(I18n.shared.string(.notInstalledHint))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Spacer()
            Toggle("", isOn: enabledBinding(for: ide))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isSupported || !installed)
                .help(helpText(for: ide))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIDE = ide
        }
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch selectedIDE {
                case .cursor:
                    CursorPage(settings: settings)
                case .claudeCode:
                    ClaudeCodePage(settings: settings)
                case .codex:
                    CodexPage(settings: settings)
                case .codeBuddy:
                    CodeBuddyPage(settings: settings)
                default:
                    placeholderView(ide: selectedIDE)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func placeholderView(ide: IDE) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ide.displayName)
                .font(.title2)
                .fontWeight(.bold)

            Text(I18n.shared.string(.comingSoon))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func enabledBinding(for ide: IDE) -> Binding<Bool> {
        Binding(
            get: { settings.isIDEEnabled(ide) },
            set: { newValue in
                // 点击开关时实时检测安装状态；未安装则不允许开启。
                refreshInstallationState()
                if newValue && !isIDEInstalled(ide) {
                    settings.setIDEEnabled(ide, enabled: false)
                    return
                }
                settings.setIDEEnabled(ide, enabled: newValue)
            }
        )
    }

    private func helpText(for ide: IDE) -> String {
        switch ide {
        case .cursor: return I18n.shared.string(.enableCursorHooks)
        case .claudeCode: return I18n.shared.string(.enableClaudeCodeHooks)
        case .codex: return I18n.shared.string(.enableCodexHooks)
        case .codeBuddy: return I18n.shared.string(.enableCodeBuddyHooks)
        default: return I18n.shared.string(.ideSupportComingSoon, ide.displayName)
        }
    }

    /// 检测各 Coding Agent 是否已安装，仅刷新 UI 状态（禁用开关、显示「未安装」角标）。
    /// 不在此处改 ideEnabled：检测路径未覆盖 pnpm/volta/fnm 等安装方式时会误关正在工作的集成。
    /// 用户主动开启时仍由各开关 binding 实时拦截未安装的 agent。
    private func refreshInstallationState() {
        cursorManager.refresh()
        claudeManager.refresh()
        codexManager.refresh()
        codeBuddyManager.refresh()
    }

    /// 某个 IDE 是否已安装（供开关禁用与「未安装」提示使用）。
    private func isIDEInstalled(_ ide: IDE) -> Bool {
        switch ide {
        case .cursor: return cursorManager.isCursorInstalled
        case .claudeCode: return claudeManager.isClaudeCodeInstalled
        case .codex: return codexManager.isCodexInstalled
        case .codeBuddy: return codeBuddyManager.isCodeBuddyInstalled
        default: return false
        }
    }
}

private struct CursorPage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n
    @ObservedObject private var engine = StateEngine.shared
    @ObservedObject private var adapter = FileHookAdapter.cursor
    @ObservedObject private var setupManager = CursorSetupManager.shared

    private var cursorEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.cursorHooksEnabled },
            set: { newValue in
                if newValue && !setupManager.isCursorInstalled {
                    settings.cursorHooksEnabled = false
                    return
                }
                settings.cursorHooksEnabled = newValue
            }
        )
    }

    private var statusText: String {
        if !adapter.isConnected {
            return I18n.shared.string(.stateDisconnected)
        }
        return engine.lastEvent == nil ? I18n.shared.string(.waitingFirstEvent) : I18n.shared.string(.running)
    }

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.featureSwitches))
                    .font(.system(size: 13, weight: .medium))
                Toggle(I18n.shared.string(.enableCursorHooks), isOn: cursorEnabledBinding)
                    .help(I18n.shared.string(.enableCursorHooks))
                    .disabled(!setupManager.isCursorInstalled)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.configuration))
                    .font(.system(size: 13, weight: .medium))
                CursorSetupSection(showCardBackgrounds: false)
                    .disabled(!settings.cursorHooksEnabled)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.cursorHooksStatus))
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(adapter.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(size: 13))
                        Spacer()
                    }

                    if let lastEvent = engine.lastEvent {
                        Text(I18n.shared.string(.recentEventFormat2, lastEvent.hook))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(I18n.shared.string(.eventsFile))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 支持的客户端（本地会话），避免用户误以为是桥接问题
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text(I18n.shared.string(.cursorSupportedClients))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.operations))
                    .font(.system(size: 13, weight: .medium))
                Button(I18n.shared.string(.clearError)) {
                    engine.clearError()
                }
                .disabled(engine.state != .error)
            }
        }
    }
}

private struct ClaudeCodePage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n
    @ObservedObject private var engine = StateEngine.shared
    @ObservedObject private var adapter = FileHookAdapter.claudeCode
    @ObservedObject private var setupManager = ClaudeCodeSetupManager.shared

    private var statusText: String {
        if !adapter.isConnected {
            return I18n.shared.string(.stateDisconnected)
        }
        return engine.lastEvent == nil ? I18n.shared.string(.waitingFirstEvent) : I18n.shared.string(.running)
    }

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.featureSwitches))
                    .font(.system(size: 13, weight: .medium))
                Toggle(I18n.shared.string(.enableClaudeCodeHooks), isOn: claudeEnabledBinding)
                    .help(I18n.shared.string(.enableClaudeCodeHooks))
                    .disabled(!setupManager.isClaudeCodeInstalled)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.configuration))
                    .font(.system(size: 13, weight: .medium))
                ClaudeSetupSection(showCardBackgrounds: false)
                    .disabled(!settings.isIDEEnabled(.claudeCode))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.claudeCodeHooksStatus))
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(adapter.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(size: 13))
                        Spacer()
                    }

                    if let lastEvent = engine.lastEvent {
                        Text(I18n.shared.string(.recentEventFormat2, lastEvent.hook))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(I18n.shared.string(.eventsFileClaude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 支持的客户端（本地会话），避免用户误以为是桥接问题
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text(I18n.shared.string(.claudeSupportedClients))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.operations))
                    .font(.system(size: 13, weight: .medium))
                Button(I18n.shared.string(.clearError)) {
                    engine.clearError()
                }
                .disabled(engine.state != .error)
            }
        }
    }

    private var claudeEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isIDEEnabled(.claudeCode) },
            set: { newValue in
                if newValue && !setupManager.isClaudeCodeInstalled {
                    settings.setIDEEnabled(.claudeCode, enabled: false)
                    return
                }
                settings.setIDEEnabled(.claudeCode, enabled: newValue)
            }
        )
    }
}

private struct CodexPage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n
    @ObservedObject private var engine = StateEngine.shared
    @ObservedObject private var adapter = FileHookAdapter.codex
    @ObservedObject private var setupManager = CodexSetupManager.shared

    private var statusText: String {
        if !adapter.isConnected {
            return I18n.shared.string(.stateDisconnected)
        }
        return engine.lastEvent == nil ? I18n.shared.string(.waitingFirstEvent) : I18n.shared.string(.running)
    }

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.featureSwitches))
                    .font(.system(size: 13, weight: .medium))
                Toggle(I18n.shared.string(.enableCodexHooks), isOn: codexEnabledBinding)
                    .help(I18n.shared.string(.enableCodexHooks))
                    .disabled(!setupManager.isCodexInstalled)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.configuration))
                    .font(.system(size: 13, weight: .medium))
                CodexSetupSection(showCardBackgrounds: false)
                    .disabled(!settings.isIDEEnabled(.codex))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.codexHooksStatus))
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(adapter.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(size: 13))
                        Spacer()
                    }

                    if let lastEvent = engine.lastEvent {
                        Text(I18n.shared.string(.recentEventFormat2, lastEvent.hook))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(I18n.shared.string(.eventsFileCodex))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Codex 无法区分成功/失败，恒 success（见 docs/codex-integration.md 限制 1）
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text(I18n.shared.string(.codexLimitNote))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            // 支持的客户端（本地会话），避免用户误以为是桥接问题
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text(I18n.shared.string(.codexSupportedClients))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.operations))
                    .font(.system(size: 13, weight: .medium))
                Button(I18n.shared.string(.clearError)) {
                    engine.clearError()
                }
                .disabled(engine.state != .error)
            }
        }
    }

    private var codexEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isIDEEnabled(.codex) },
            set: { newValue in
                if newValue && !setupManager.isCodexInstalled {
                    settings.setIDEEnabled(.codex, enabled: false)
                    return
                }
                settings.setIDEEnabled(.codex, enabled: newValue)
            }
        )
    }
}

private struct CodeBuddyPage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n
    @ObservedObject private var engine = StateEngine.shared
    @ObservedObject private var adapter = FileHookAdapter.codeBuddy
    @ObservedObject private var setupManager = CodeBuddySetupManager.shared

    private var statusText: String {
        if !adapter.isConnected {
            return I18n.shared.string(.stateDisconnected)
        }
        return engine.lastEvent == nil ? I18n.shared.string(.waitingFirstEvent) : I18n.shared.string(.running)
    }

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.featureSwitches))
                    .font(.system(size: 13, weight: .medium))
                Toggle(I18n.shared.string(.enableCodeBuddyHooks), isOn: codebuddyEnabledBinding)
                    .help(I18n.shared.string(.enableCodeBuddyHooks))
                    .disabled(!setupManager.isCodeBuddyInstalled)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.configuration))
                    .font(.system(size: 13, weight: .medium))
                CodeBuddySetupSection(showCardBackgrounds: false)
                    .disabled(!settings.isIDEEnabled(.codeBuddy))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.codebuddyHooksStatus))
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(adapter.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(size: 13))
                        Spacer()
                    }

                    if let lastEvent = engine.lastEvent {
                        Text(I18n.shared.string(.recentEventFormat2, lastEvent.hook))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(I18n.shared.string(.eventsFileCodebuddy))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // CodeBuddy 无法区分成功/失败，恒 success（见 docs/codebuddy-integration.md 限制 1）
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text(I18n.shared.string(.codebuddyLimitNote))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            // 支持的客户端（本地会话），避免用户误以为是桥接问题
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text(I18n.shared.string(.codebuddySupportedClients))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.operations))
                    .font(.system(size: 13, weight: .medium))
                Button(I18n.shared.string(.clearError)) {
                    engine.clearError()
                }
                .disabled(engine.state != .error)
            }
        }
    }

    private var codebuddyEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isIDEEnabled(.codeBuddy) },
            set: { newValue in
                if newValue && !setupManager.isCodeBuddyInstalled {
                    settings.setIDEEnabled(.codeBuddy, enabled: false)
                    return
                }
                settings.setIDEEnabled(.codeBuddy, enabled: newValue)
            }
        )
    }
}

private struct ColorsPage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n
    @State private var isEditing: Bool = false
    @State private var hoveredState: LiangState? = nil
    @State private var selectedState: LiangState? = nil

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(I18n.shared.string(.stateColors))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if isEditing {
                    Button(I18n.shared.string(.save)) {
                        exitEditMode()
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(I18n.shared.string(.edit)) {
                        enterEditMode()
                    }
                    .controlSize(.small)
                }
            }

            if isEditing {
                GroupBox {
                    editingContent
                } label: {
                    EmptyView()
                }
            } else {
                readOnlyContent
                    .padding(4)
            }
        }
        .onDisappear {
            if GlowController.shared.previewState != nil {
                GlowController.shared.previewState = nil
                GlowController.shared.apply()
            }
        }
    }

    private var readOnlyContent: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(LiangState.allCases, id: \.self) { state in
                VStack(spacing: 8) {
                    Circle()
                        .fill(stateColor(state))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                        .opacity(settings.isStateGlowEnabled(state) ? 1 : 0.35)
                        .help(stateHex(state))
                    Text(state.localizedName)
                        .font(.system(size: 12))
                        .opacity(settings.isStateGlowEnabled(state) ? 1 : 0.45)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .cornerRadius(10)
            }
        }
        .padding(4)
    }

    private var editingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(LiangState.allCases, id: \.self) { state in
                    VStack(spacing: 8) {
                        CompactColorPicker(color: colorBinding(for: state))
                            .frame(width: 28, height: 28)
                            .help(stateHex(state))
                        Text(state.localizedName)
                            .font(.system(size: 12))
                        Toggle(I18n.shared.string(.show), isOn: enabledBinding(for: state))
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        (hoveredState == state || selectedState == state)
                            ? Color.secondary.opacity(0.12)
                            : Color.clear
                    )
                    .cornerRadius(10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedState = state
                        GlowController.shared.previewState = state
                    }
                    .onHover { isHover in
                        hoveredState = isHover ? state : nil
                    }
                }
            }
            .onChange(of: settings.stateColors) { oldColors, newColors in
                // 当用户在色盘中调整颜色时，自动将光晕切换到被编辑的状态。
                if let changed = LiangState.allCases.first(where: {
                    !colorsEqual(newColors[$0], oldColors[$0])
                }) {
                    selectedState = changed
                    GlowController.shared.previewState = changed
                }
            }

            HStack(spacing: 12) {
                Button(I18n.shared.string(.resetDefaultColors)) {
                    settings.stateColors = StateAppearance.defaultColors
                }
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(4)
    }

    private func enterEditMode() {
        GlowController.shared.previewState = nil
        selectedState = nil
        hoveredState = nil
        isEditing = true
    }

    private func exitEditMode() {
        GlowController.shared.previewState = nil
        selectedState = nil
        hoveredState = nil
        GlowController.shared.apply()
        isEditing = false
    }

    private func stateColor(_ state: LiangState) -> Color {
        settings.stateColors[state]?.swiftUIColor()
            ?? StateAppearance.defaultColors[state]?.swiftUIColor()
            ?? .gray
    }

    private func stateHex(_ state: LiangState) -> String {
        settings.stateColors[state]?.toHex()
            ?? StateAppearance.defaultColors[state]?.toHex()
            ?? "#808080"
    }

    private func colorBinding(for state: LiangState) -> Binding<Color> {
        Binding(
            get: {
                settings.stateColors[state]?.swiftUIColor()
                    ?? StateAppearance.defaultColors[state]?.swiftUIColor()
                    ?? .gray
            },
            set: { newColor in
                settings.stateColors[state] = newColor.resolvedNSColor()
            }
        )
    }

    private func enabledBinding(for state: LiangState) -> Binding<Bool> {
        Binding(
            get: { settings.isStateGlowEnabled(state) },
            set: { settings.setStateGlowEnabled(state, enabled: $0) }
        )
    }

    private func colorsEqual(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l?, r?): return l.isEqual(r)
        default: return false
        }
    }
}

private struct AdvancedPage: View {
    @ObservedObject var settings: GlowSettings
    @EnvironmentObject var i18n: I18n

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.stateEngineParameters))
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 14) {
                    sliderRow(
                        I18n.shared.string(.processingTimeout) + " (s)",
                        help: I18n.shared.string(.processingTimeoutHelp),
                        value: $settings.processingTimeout, range: 10...300, step: 5
                    )
                    sliderRow(
                        I18n.shared.string(.successDuration) + " (s)",
                        help: I18n.shared.string(.successDurationHelp),
                        value: $settings.successMaxDuration, range: 10...600, step: 10
                    )
                    sliderRow(
                        I18n.shared.string(.deduplicationWindow) + " (s)",
                        help: I18n.shared.string(.deduplicationWindowHelp),
                        value: $settings.deduplicationWindow, range: 0.2...5, step: 0.1
                    )
                    HStack(spacing: 4) {
                        Toggle(I18n.shared.string(.enableWaitingTimeout), isOn: $settings.waitingTimeoutEnabled)
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .help(I18n.shared.string(.waitingTimeoutHelp))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.diagnostics))
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 10) {
                    Button(I18n.shared.string(.copyConfigToClipboard)) {
                        copyConfiguration(settings: settings)
                    }
                    Text(I18n.shared.string(.diagnosticsDescription))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.restoreAllDefaults))
                    .font(.system(size: 13, weight: .medium))
                Button(I18n.shared.string(.restoreAllDefaults)) {
                    settings.restoreDefaults()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(I18n.shared.string(.language))
                    .font(.system(size: 13, weight: .medium))
                LanguagePicker()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct LanguagePicker: View {
    @EnvironmentObject var i18n: I18n

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { language in
                Button(language.displayName) {
                    i18n.currentLanguage = language
                }
                .buttonStyle(LanguageSegmentButtonStyle(isSelected: i18n.currentLanguage == language))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

private struct LanguageSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(isSelected ? Color(NSColor.controlAccentColor) : Color.clear)
            .foregroundColor(isSelected ? .white : (configuration.isPressed ? .secondary : .primary))
    }
}

private struct AboutPage: View {
    @EnvironmentObject var i18n: I18n

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.shared.string(.appName))
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 6) {
                    Text(I18n.shared.string(.versionFormat, "0.1.9"))
                        .font(.system(size: 13))
                    Text(I18n.shared.string(.aboutTitle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(I18n.shared.string(.aboutSubtitle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(I18n.shared.string(.madeWithLove))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GroupBox(I18n.shared.string(.changelog)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(I18n.shared.string(.changelogPlaceholder))
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding(4)
            }
        }
    }
}

// MARK: - Helpers

@ViewBuilder
private func sliderRow(_ title: String, help: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
            if let help {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .help(help)
            }
            Spacer()
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        Slider(value: value, in: range, step: step)
    }
}

private func copyConfiguration(settings: GlowSettings) {
    let idleColor = settings.stateColors[.idle]?.toHex()
        ?? StateAppearance.defaultColors[.idle]?.toHex()
        ?? "#FF9229"
    var colorLines: [String] = []
    for state in LiangState.allCases {
        let hex = settings.stateColors[state]?.toHex()
            ?? StateAppearance.defaultColors[state]?.toHex()
            ?? "#808080"
        colorLines.append("\(state.rawValue): \(hex)")
    }

    let config = """
    glowEnabled: \(settings.glowEnabled)
    cursorHooksEnabled: \(settings.cursorHooksEnabled)
    cursorGlowEnabled: \(settings.cursorGlowEnabled)
    cursorGlowSize: \(String(format: "%.0f", settings.cursorGlowSize))
    cursorGlowOffsetX: \(String(format: "%.0f", settings.cursorGlowOffsetX))
    cursorGlowOffsetY: \(String(format: "%.0f", settings.cursorGlowOffsetY))
    brightness: \(String(format: "%.2f", settings.brightness))
    blurRadius: \(String(format: "%.1f", settings.blurRadius))
    outerThickness: \(String(format: "%.1f", settings.outerThickness))
    innerThickness: \(String(format: "%.1f", settings.innerThickness))
    notchInset: \(String(format: "%.1f", settings.notchInset))
    horizontalOffset: \(String(format: "%.1f", settings.horizontalOffset))
    cornerRadiusScale: \(String(format: "%.2f", settings.cornerRadiusScale))
    idleColor: \(idleColor)
    breathingEnabled: \(settings.breathingEnabled)
    breathingSpeed: \(String(format: "%.2f", settings.breathingSpeed))
    processingTimeout: \(String(format: "%.0f", settings.processingTimeout))
    successMaxDuration: \(String(format: "%.0f", settings.successMaxDuration))
    waitingTimeoutEnabled: \(settings.waitingTimeoutEnabled)
    deduplicationWindow: \(String(format: "%.1f", settings.deduplicationWindow))
    stateColors:\n\(colorLines.map { "  - \($0)" }.joined(separator: "\n"))
    stateGlowEnabled:\n\(LiangState.allCases.map { "  - \($0.rawValue): \(settings.isStateGlowEnabled($0))" }.joined(separator: "\n"))
    ideEnabled:\n\(IDE.allCases.map { "  - \($0.rawValue): \(settings.isIDEEnabled($0))" }.joined(separator: "\n"))
    """
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(config, forType: .string)
}
