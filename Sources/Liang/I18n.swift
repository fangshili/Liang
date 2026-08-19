import Foundation
import Combine

/// 应用支持的语言。新增语言时只需在这里扩展并补充 `ChineseTranslations.table` 中的翻译。
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

/// 集中式国际化管理器。
/// 使用 `I18n.shared.string(.key)` 获取当前语言的字符串；支持 `%@`、`%d`、`%.0f` 等 format。
final class I18n: ObservableObject {
    static let shared = I18n()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.languageKey)
        }
    }

    private static let languageKey = "com.liang.language"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.languageKey),
           let stored = AppLanguage(rawValue: raw) {
            currentLanguage = stored
        } else {
            currentLanguage = I18n.systemMatchingLanguage()
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.languageKey)
        }
    }

    /// 根据系统首选语言匹配默认语言；中文变体统一映射为中文，其他默认英文。
    static func systemMatchingLanguage() -> AppLanguage {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else { return .english }
        if preferred.hasPrefix("zh") { return .chinese }
        return .english
    }

    func string(_ key: LocalizedKey) -> String {
        switch currentLanguage {
        case .english:
            return EnglishTranslations.table[key] ?? key.rawValue
        case .chinese:
            return ChineseTranslations.table[key] ?? key.rawValue
        }
    }

    func string(_ key: LocalizedKey, _ args: CVarArg...) -> String {
        String(format: string(key), arguments: args)
    }
}

/// 所有面向用户的字符串 key。
/// 英文文案通常直接作为 enum 的 rawValue；与已有 key 冲突或需要单独定制时，通过 `EnglishTranslations.table` 覆盖。
enum LocalizedKey: String {
    // MARK: - Common
    case appName = "Liang"
    case settingsWindowTitle = "Liang Settings"
    case settings = "Settings..."
    case about = "About"
    case advanced = "Advanced"
    case general = "General"
    case glow = "Glow"
    case codingAgent = "Coding Agent"
    case stateColors = "State Colors"
    case language = "Language"
    case cancel = "Cancel"
    case confirm = "Confirm"
    case done = "Done"
    case save = "Save"
    case edit = "Edit"
    case copy = "Copy"
    case copied = "Copied"
    case copyFailed = "Copy Failed"
    case restore = "Restore"
    case restoreDefaults = "Restore Defaults"
    case resetToDefault = "Reset to Default"
    case version = "Version"
    case comingSoon = "Coming soon"
    case enabled = "Enabled"
    case disabled = "Disabled"
    case show = "Show"
    case hide = "Hide"
    case yes = "Yes"
    case no = "No"
    case ok = "OK"
    case expand = "Expand"
    case collapse = "Collapse"
    case staticCheck = "Static Check"
    case configCheck = "Configuration Check"
    case installConfirmTitle = "Install Confirmation"
    case installSuccess = "Installation completed"

    // MARK: - Status Bar
    case statusFormat = "Status: %@"
    case recentEventNone = "Recent Event: None"
    case recentEventFormat = "Recent Event: %@ %@"
    case clearError = "Clear Error State"
    case checkForUpdates = "Check for Updates..."
    case quitApp = "Quit Liang"

    // MARK: - States
    case stateIdle = "Idle"
    case stateProcessing = "Processing"
    case stateWaiting = "Waiting"
    case stateSuccess = "Success"
    case stateError = "Error"
    case stateUnknown = "Unknown"
    case stateDisconnected = "Disconnected"

    // MARK: - Cursor Label
    case cursorLabelProcessing = "cursorLabel.processing"
    case cursorLabelDone = "cursorLabel.done"
    case cursorLabelFail = "cursorLabel.fail"
    case cursorLabelWaiting = "cursorLabel.waiting"

    // MARK: - Task List
    case noRunningTasks = "No running tasks"
    case justNow = "Just now"
    case minutesAgo = "%d min ago"
    case hoursAgo = "%d hr ago"
    case daysAgo = "%d days ago"
    case taskSessionStart = "Start Session"
    case taskSubmitPrompt = "Submit Prompt"
    case taskSessionEnd = "End Session"
    case taskWaitingInput = "Waiting Input"
    case taskThinking = "Thinking"
    case taskSubtask = "Subtask"
    case taskTaskEnd = "Task End"
    case toolReadFile = "Read File"
    case toolWriteFile = "Write File"
    case toolEditFile = "Edit File"
    case toolSearchFile = "Search File"
    case toolSearchContent = "Search Content"
    case toolExecuteCommand = "Execute Command"
    case toolWebSearch = "Web Search"
    case toolWebFetch = "Fetch Webpage"
    case toolAskUser = "Ask User"
    case toolCallTool = "Call Tool"

    // MARK: - Settings - Glow
    case notchGlow = "Notch Glow"
    case cursorGlow = "Cursor Glow"
    case menuBar = "Menu Bar"
    case enableNotchGlow = "Enable Notch Glow"
    case enableCursorGlow = "Enable Cursor Follow Glow"
    case showCursorLabel = "Show status label beside cursor"
    case enableMenuBarStateColor = "Enable menu bar icon state color"
    case notchGlowHelp = "Hide notch glow when disabled"
    case cursorGlowHelp = "Hide cursor glow when disabled"
    case menuBarStateColorHelp = "Show a white static glow orb when disabled"
    case notchSize = "Notch Size"
    case noNotchDetected = "No notch detected"
    case widthPt = "Width: %.0f pt"
    case heightPt = "Height: %.0f pt"
    case breathingSpeed = "Breathing Speed"
    case glowBrightness = "Glow Brightness"
    case blurRadius = "Blur Radius"
    case outerThickness = "Outer Thickness"
    case innerThickness = "Inner Thickness"
    case horizontalOffset = "Horizontal Offset"
    case verticalOffset = "Vertical Offset"
    case notchInset = "Notch Inset"
    case cornerRadiusScale = "Corner Radius Scale"
    case hue = "Hue"
    case saturation = "Saturation"
    case brightness = "Brightness"
    case breathingEnabled = "Breathing"
    case cursorSize = "Size"
    case breathingAnimation = "Breathing Animation"
    case advancedSettings = "Advanced Settings"
    case breathingSettingsHelp = "Only affects Idle and Processing states"

    // MARK: - Settings - Advanced
    case stateEngineParameters = "State Engine Parameters"
    case processingTimeout = "Processing Timeout"
    case successDuration = "Success Duration"
    case enableWaitingTimeout = "Enable Waiting Timeout"
    case waitingTimeoutHelp = "Off by default; waiting persists until the user sends the next message"
    case processingTimeoutHelp = "If no new event is received while in the processing state for longer than this duration, the glow automatically returns to idle."
    case successDurationHelp = "The maximum time the success glow is kept before automatically returning to idle."
    case deduplicationWindowHelp = "Events of the same type or within the same conversation that arrive within this window are treated as a single event to prevent flickering."
    case deduplicationWindow = "Deduplication Window"
    case diagnostics = "Diagnostics"
    case diagnosticsDescription = "Export current configuration as text for troubleshooting."
    case copyConfigToClipboard = "Copy Configuration to Clipboard"
    case restoreAllDefaults = "Restore All Defaults"
    case restoreAllDefaultsMessage = "Restore all settings to defaults? This action cannot be undone."

    // MARK: - Settings - State Colors
    case stateColorDescription = "Customize the color and visibility of each state."
    case restoreColorToDefault = "Restore color to default"
    case resetDefaultColors = "Reset Default Colors"
    case configCopied = "Configuration copied to clipboard"

    // MARK: - Settings - IDE / Cursor
    case enableCursorHooks = "Enable Cursor Hooks"
    case featureSwitches = "Feature Switches"
    case configuration = "Configuration"
    case cursorHooksStatus = "Cursor Hooks Status"
    case operations = "Operations"
    case waitingFirstEvent = "Waiting for first event"
    case running = "Running"
    case recentEventFormat2 = "Recent Event: %@"
    case eventsFile = "Events file: ~/.liang/cursor-events.jsonl"
    case recheck = "Recheck"
    case dynamicCheck = "Dynamic Check"
    case dynamicCheckHint = "Click \"New Agent\" or send a message in Cursor. Liang will listen for events within 30 seconds."
    case dynamicCheckSuccess = "Event received. Configuration successful!"
    case dynamicCheckFailure = "No event detected. Please check the configuration or fully restart Cursor and try again."
    case autoInstall = "Auto Install"
    case autoInstallDescription = "Automatically write ~/.cursor/hooks.json and the bridge script. Liang will not read or upload any code, prompts, or file contents."
    case oneClickConfigure = "Configure Cursor"
    case configure = "Configure"
    case installing = "Installing…"
    case manualInstall = "Manual Install"
    case manualInstallDescription = "Copy the configuration and paste it into ~/.cursor/hooks.json, then fully restart Cursor."
    case viewSteps = "View Steps"
    case permissionAlertTitle = "Cursor configuration required"
    case permissionAlertMessage = "Liang will write to ~/.cursor/hooks.json and ~/.cursor/hooks/liang-bridge.sh to receive Cursor Hook events. This will not read or upload your code, prompts, or file contents."
    case continueAction = "Continue"
    case waitingForEvents = "Waiting for events…"
    case dynamicCheckSuccess2 = "Cursor event received, configuration is active"
    case dynamicCheckFailure2 = "No event received. Make sure Cursor is fully restarted and hooks.json is correct."
    case dynamicCheckHint2 = "After clicking Start Check, click \"New Agent\" or send a message in Cursor."
    case startCheck = "Start Check"
    case clearResult = "Clear Result"
    case checking = "Checking…"
    case notConfigured = "Not Configured"
    case partialConfig = "Partial Configuration"
    case configured = "Configured"
    case checkingHooksJson = "Checking ~/.cursor/hooks.json"
    case missingHooksFormat = "Missing %d hook(s): %@"
    case bridgeScriptFormat = "Bridge script: %@"
    case manualInstallSheetTitle = "Manual Configure Cursor Hooks"
    case step1ScriptPath = "1. Place the bridge script at the following path and make it executable:"
    case step2HooksJson = "2. Write the following to ~/.cursor/hooks.json:"
    case step3RestartCursor = "3. Fully quit and restart Cursor (Cmd+Q then reopen)."
    case later = "Later"
    case scriptExists = "Script exists"
    case scriptExecutable = "Script executable"
    case hooksJsonExists = "hooks.json exists"
    case requiredHooksComplete = "Required hooks complete"
    case versionMatches = "Version matches"
    case openCursorFolder = "Open ~/.cursor folder"
    case copyHooksJson = "Copy hooks.json"
    case installConfirmMessage = "This will write to ~/.cursor/hooks.json and ~/.cursor/hooks/liang-bridge.sh, replacing any existing configuration. Continue?"
    case cursor = "Cursor"
    case ideSupportComingSoon = "%@ support is coming soon"
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case codebuddy = "CodeBuddy"
    case trae = "Trae"

    // MARK: - Settings - About
    case aboutTitle = "macOS Coding Agent Glow Assistant"
    case aboutSubtitle = "Show AI running state through different glow effects"
    case madeWithLove = "Made with ❤️"
    case versionFormat = "Version %@"
    case changelog = "Changelog"
    case changelogPlaceholder = "Future updates will be shown here."

    // MARK: - Errors
    case cannotOpenEventsFile = "Cannot open events file: %@"
    case eventsFileDecodeFailed = "Failed to decode events file"
    case cursorSetupMissingHooksJson = "~/.cursor/hooks.json not detected"
    case cursorSetupInvalidHooksJson = "~/.cursor/hooks.json format is invalid"
    case cursorSetupMissingBridgePath = "Bridge script path not resolved"
    case cursorSetupScriptMissing = "Bridge script missing: %@"
    case cursorSetupScriptNotExecutable = "Bridge script is not executable"
    case cursorSetupResourceMissing = "Bridge script not found in app bundle. Try manual installation."
    case cursorSetupWriteFailed = "Write failed: %@"

    // MARK: - Onboarding V2
    case onboardingConnectorTitle = "Onboarding · Connector Title"
    case onboardingConnectorSubtitle = "Onboarding · Connector Subtitle"
    case onboardingGlowTitle = "Onboarding · Glow Title"
    case onboardingGlowSubtitle = "Onboarding · Glow Subtitle"
    case onboardingNext = "Next"
    case onboardingBack = "Back"
    case onboardingStartUsing = "Start Using Liang"
    case onboardingSkip = "Skip for now"
    case onboardingSetupLater = "Maybe later"
    case onboardingCursorCardTitle = "Onboarding · Cursor Card Title"
    case onboardingCursorCardDesc = "Onboarding · Cursor Card Description"
    case onboardingOtherAgentsTitle = "Onboarding · Other Agents Title"
    case onboardingOtherAgentsHint = "Onboarding · Other Agents Hint"
    case onboardingOtherComingSoon = "Onboarding · Other Agents Coming Soon"
    case onboardingThanksTitle = "Onboarding · Thanks Title"
    case onboardingThanksBody = "Onboarding · Thanks Body"
    case onboardingThanksClose = "Onboarding · Thanks Close"
    case onboardingNotchCardTitle = "Onboarding · Notch Card Title"
    case onboardingNotchCardDesc = "Onboarding · Notch Card Description"
    case onboardingCursorGlowCardTitle = "Onboarding · Cursor Glow Card Title"
    case onboardingCursorGlowCardDesc = "Onboarding · Cursor Glow Card Description"
    case onboardingMenuBarCardTitle = "Onboarding · Menu Bar Card Title"
    case onboardingMenuBarCardDesc = "Onboarding · Menu Bar Card Description"
    case onboardingNotAvailableMac = "Not available on this Mac"
    case onboardingStateBadgeIdle = "IDLE"
    case onboardingStateBadgeProcessing = "PROCESSING"
    case onboardingStateBadgeSuccess = "SUCCESS"
    case onboardingPreviewLoopHint = "Onboarding · Preview Loop Hint"
    case onboardingPreviewActive = "Onboarding · Preview Active"
    case onboardingCursorConnected = "Onboarding · Cursor Connected"
    case onboardingCursorNotInstalledTitle = "Cursor Not Installed"
    case onboardingCursorNotInstalledMessage = "Liang requires Cursor to receive agent events. Please install Cursor first, or continue if Cursor is already installed but not detected."
    case onboardingCursorNotInstalledContinue = "Continue Anyway"
    case onboardingCursorNotInstalledDownload = "Download Cursor"
    case glowTabGeneral = "Glow Tab General"
    case glowTabNotch = "Glow Tab Notch"
    case glowTabCursor = "Glow Tab Cursor"
    case glowTabMenuBar = "Glow Tab Menu Bar"
    case cursorSetupStatusConfigured = "Cursor Setup Status Configured"
    case cursorSetupStatusMissing = "Cursor Setup Status Missing"
    case cursorSetupStatusPartial = "Cursor Setup Status Partial"
    case cursorSetupStatusNotConfigured = "Cursor Setup Status Not Configured"
    case cursorSetupStatusChecking = "Cursor Setup Status Checking"

    // MARK: - Onboarding V1
    case onboardingWindowTitle = "Configure Cursor Hooks"
    case welcomeTitle = "Welcome to Liang"
    case welcomeBody = "Liang needs Cursor Hooks to get the working status and show glow hints in the notch."
    case setupCompleteTitle = "Setup Complete"
    case setupCompleteBody = "Cursor Hooks is configured. You can change it later in Settings."

    // MARK: - Settings - IDE / Claude Code
    case enableClaudeCodeHooks = "Enable Claude Code Hooks"
    case claudeCodeHooksStatus = "Claude Code Hooks Status"
    case eventsFileClaude = "Events file: ~/.liang/claude-events.jsonl"
    case claudeInstallDescription = "Automatically write ~/.claude/settings.json and the bridge script. Liang will not read or upload any code, prompts, or file contents."
    case claudeInstallConfirmMessage = "This will write to ~/.claude/settings.json and ~/.claude/hooks/claude-bridge.sh, preserving your other Claude Code settings. Continue?"
    case claudeSetupMissingSettingsJson = "~/.claude/settings.json not detected"
    case claudeSetupInvalidSettingsJson = "~/.claude/settings.json format is invalid"
    case onboardingClaudeCardDesc = "Claude Code hooks cover session, tool, and agent states, so Liang reacts the moment your terminal agent is working."
    case onboardingClaudeNotInstalledTitle = "Claude Code Not Installed"
    case onboardingClaudeNotInstalledMessage = "Liang requires the Claude Code CLI to receive agent events. Please install Claude Code first, or continue if it is already installed but not detected."
    case onboardingClaudeNotInstalledDownload = "Install Claude Code"
}

// MARK: - English Translations

private enum EnglishTranslations {
    static let table: [LocalizedKey: String] = [
        .cursorLabelProcessing: "Processing",
        .cursorLabelDone: "Done",
        .cursorLabelFail: "Fail",
        .cursorLabelWaiting: "Waiting",
        .checkForUpdates: "Check for Updates...",
        // Onboarding V2
        .onboardingConnectorTitle: "Connect a Coding Agent",
        .onboardingConnectorSubtitle: "Liang listens to your agent in real time. Set up Cursor to enable the glow.",
        .onboardingGlowTitle: "Choose your glow",
        .onboardingGlowSubtitle: "Each glow reacts to your agent in real time. Toggle on what fits you.",
        .onboardingCursorCardTitle: "Cursor",
        .onboardingCursorCardDesc: "Cursor hooks cover every meaningful state, so Liang reacts the moment your agent is working.",
        .onboardingOtherAgentsTitle: "Other agents",
        .onboardingOtherAgentsHint: "Codex CLI · CodeBuddy · Trae",
        .onboardingOtherComingSoon: "Coming soon...",
        .onboardingThanksTitle: "👋 Thanks for installing Liang!",
        .onboardingThanksBody: "You can change your preferences anytime from the menu bar.\\nMay a tiny glow keep you company while coding alone ❤️",
        .onboardingThanksClose: "Close",
        .onboardingNotchCardTitle: "Notch Glow",
        .onboardingNotchCardDesc: "A colored ring outlines the MacBook notch, reflecting the AI state in real time.",
        .onboardingCursorGlowCardTitle: "Cursor Glow",
        .onboardingCursorGlowCardDesc: "A luminous radial aura that follows your mouse pointer.",
        .onboardingMenuBarCardTitle: "Menu Bar Status Color",
        .onboardingMenuBarCardDesc: "The Liang icon in your menu bar pulses and changes color with AI state.",
        .onboardingPreviewActive: "Previewing...",
        .onboardingCursorConnected: "Bridge Installed",
        .onboardingCursorNotInstalledTitle: "Cursor Not Installed",
        .onboardingCursorNotInstalledMessage: "Liang requires Cursor to receive agent events. Please install Cursor first, or continue if Cursor is already installed but not detected.",
        .onboardingCursorNotInstalledContinue: "Continue Anyway",
        .onboardingCursorNotInstalledDownload: "Download Cursor",
        .glowTabGeneral: "General",
        .glowTabNotch: "Notch",
        .glowTabCursor: "Cursor",
        .glowTabMenuBar: "Menu Bar",
        .cursorSetupStatusConfigured: "Configured",
        .cursorSetupStatusMissing: "Incomplete (missing files)",
        .cursorSetupStatusPartial: "Incomplete (hooks missing)",
        .cursorSetupStatusNotConfigured: "Not Configured",
        .cursorSetupStatusChecking: "Checking..."
    ]
}

// MARK: - Chinese Translations

private enum ChineseTranslations {
    static let table: [LocalizedKey: String] = [
        .appName: "Liang",
        .settingsWindowTitle: "Liang 设置",
        .settings: "设置...",
        .about: "关于",
        .advanced: "高级",
        .general: "通用",
        .glow: "光晕",
        .codingAgent: "Coding Agent",
        .stateColors: "状态颜色",
        .language: "语言",
        .cancel: "取消",
        .confirm: "确定",
        .done: "完成",
        .save: "保存",
        .edit: "编辑",
        .copy: "复制",
        .copied: "已复制",
        .copyFailed: "复制失败",
        .restore: "恢复",
        .restoreDefaults: "恢复默认",
        .resetToDefault: "恢复默认",
        .version: "版本",
        .comingSoon: "敬请期待",
        .enabled: "已启用",
        .disabled: "已禁用",
        .show: "显示",
        .hide: "隐藏",
        .yes: "是",
        .no: "否",
        .ok: "好",
        .expand: "展开",
        .collapse: "收起",
        .staticCheck: "静态检测",
        .configCheck: "配置检测",
        .installConfirmTitle: "安装确认",
        .installSuccess: "安装完成",
        .statusFormat: "状态：%@",
        .recentEventNone: "最近事件：无",
        .recentEventFormat: "最近事件：%@ %@",
        .clearError: "清除错误状态",
        .checkForUpdates: "检查更新...",
        .quitApp: "退出 Liang",
        .stateIdle: "空闲",
        .stateProcessing: "处理中",
        .stateWaiting: "等待确认",
        .stateSuccess: "成功",
        .stateError: "错误",
        .stateUnknown: "未知",
        .stateDisconnected: "未连接",
        .cursorLabelProcessing: "处理中",
        .cursorLabelDone: "完成",
        .cursorLabelFail: "失败",
        .cursorLabelWaiting: "等待中",
        .noRunningTasks: "暂无进行中的任务",
        .justNow: "刚刚",
        .minutesAgo: "%d 分前",
        .hoursAgo: "%d 小时前",
        .daysAgo: "%d 天前",
        .taskSessionStart: "开始会话",
        .taskSubmitPrompt: "提交问题",
        .taskSessionEnd: "结束会话",
        .taskWaitingInput: "等待输入",
        .taskThinking: "思考中",
        .taskSubtask: "子任务",
        .taskTaskEnd: "任务结束",
        .toolReadFile: "读取文件",
        .toolWriteFile: "写入文件",
        .toolEditFile: "编辑文件",
        .toolSearchFile: "搜索文件",
        .toolSearchContent: "搜索内容",
        .toolExecuteCommand: "执行命令",
        .toolWebSearch: "网络搜索",
        .toolWebFetch: "获取网页",
        .toolAskUser: "询问用户",
        .toolCallTool: "调用工具",
        .notchGlow: "刘海光晕",
        .cursorGlow: "光标光晕",
        .menuBar: "菜单栏",
        .enableNotchGlow: "启用刘海光晕",
        .enableCursorGlow: "启用光标跟随光晕",
        .showCursorLabel: "在光标旁显示状态标签",
        .enableMenuBarStateColor: "启用菜单栏图标状态色",
        .notchGlowHelp: "关闭后隐藏刘海光晕",
        .cursorGlowHelp: "关闭后隐藏光标光晕",
        .menuBarStateColorHelp: "关闭后菜单栏图标显示为白色静态光晕小球",
        .notchSize: "刘海尺寸",
        .noNotchDetected: "未检测到刘海",
        .widthPt: "宽度：%.0f pt",
        .heightPt: "高度：%.0f pt",
        .breathingSpeed: "呼吸速度",
        .glowBrightness: "光晕亮度",
        .blurRadius: "模糊半径",
        .outerThickness: "外环厚度",
        .innerThickness: "内环厚度",
        .horizontalOffset: "水平偏移",
        .verticalOffset: "垂直偏移",
        .notchInset: "刘海贴合",
        .cornerRadiusScale: "圆角弧度",
        .hue: "色相",
        .saturation: "饱和度",
        .brightness: "亮度",
        .breathingEnabled: "呼吸效果",
        .cursorSize: "大小",
        .breathingAnimation: "呼吸动画",
        .advancedSettings: "高级设置",
        .breathingSettingsHelp: "仅对 空闲/进行中 状态生效",
        .stateEngineParameters: "状态引擎参数",
        .processingTimeout: "Processing 超时",
        .successDuration: "Success 保持时间",
        .enableWaitingTimeout: "启用 Waiting 超时",
        .waitingTimeoutHelp: "默认关闭，waiting 会保持到用户发送下一条消息",
        .processingTimeoutHelp: "processing 状态下超过该时长没有新事件时，光晕自动回到 idle。",
        .successDurationHelp: "success 状态最多保持该时长，之后自动回到 idle。",
        .deduplicationWindowHelp: "相同类型或同一会话的事件在该时间窗口内到达时，会被合并为一次事件，避免光晕频繁闪烁。",
        .deduplicationWindow: "去重窗口",
        .diagnosticsDescription: "将当前所有配置以文本形式导出，便于排查问题。",
        .diagnostics: "诊断",
        .copyConfigToClipboard: "复制配置到剪贴板",
        .restoreAllDefaults: "恢复所有默认设置",
        .restoreAllDefaultsMessage: "确定要恢复所有默认设置吗？此操作不可撤销。",
        .stateColorDescription: "自定义每个状态的颜色与可见性。",
        .restoreColorToDefault: "将颜色恢复为默认",
        .resetDefaultColors: "重置默认颜色",
        .configCopied: "配置已复制到剪贴板",
        .enableCursorHooks: "启用 Cursor Hooks",
        .featureSwitches: "功能开关",
        .configuration: "配置",
        .cursorHooksStatus: "Cursor Hooks 状态",
        .operations: "操作",
        .waitingFirstEvent: "等待首个事件",
        .running: "运行中",
        .recentEventFormat2: "最近事件：%@",
        .eventsFile: "事件文件：~/.liang/cursor-events.jsonl",
        .recheck: "重新检测",
        .dynamicCheck: "动态检测",
        .dynamicCheckHint: "请在 Cursor 中点击「New Agent」或发送一条消息，Liang 将在 30 秒内监听事件。",
        .dynamicCheckSuccess: "已收到事件，配置成功！",
        .dynamicCheckFailure: "未检测到事件，请检查配置或完全重启 Cursor 后重试。",
        .autoInstall: "自动安装",
        .autoInstallDescription: "由 Liang 自动写入 ~/.cursor/hooks.json 和桥接脚本。不会读取或上传任何代码、prompt、文件内容。",
        .oneClickConfigure: "一键配置 Cursor",
        .configure: "配置",
        .installing: "安装中…",
        .manualInstall: "手动安装",
        .manualInstallDescription: "复制配置自行粘贴到 ~/.cursor/hooks.json，然后完全重启 Cursor。",
        .viewSteps: "查看步骤",
        .permissionAlertTitle: "需要写入 Cursor 配置",
        .permissionAlertMessage: "Liang 将写入 ~/.cursor/hooks.json 和 ~/.cursor/hooks/liang-bridge.sh，用于接收 Cursor Hook 事件。该操作不会读取或上传你的代码、prompt 或文件内容。",
        .continueAction: "继续",
        .waitingForEvents: "等待事件中…",
        .dynamicCheckSuccess2: "已收到 Cursor 事件，配置生效",
        .dynamicCheckFailure2: "未收到事件，请确认 Cursor 已完全重启且 hooks.json 配置正确",
        .dynamicCheckHint2: "点击「开始检测」后，请在 Cursor 中点击「New Agent」或发送一条消息。",
        .startCheck: "开始检测",
        .clearResult: "清除结果",
        .checking: "检测中…",
        .notConfigured: "未配置",
        .partialConfig: "配置不完整",
        .configured: "已配置",
        .checkingHooksJson: "正在检查 ~/.cursor/hooks.json",
        .missingHooksFormat: "缺少 %d 个 Hook：%@",
        .bridgeScriptFormat: "桥接脚本：%@",
        .manualInstallSheetTitle: "手动配置 Cursor Hooks",
        .step1ScriptPath: "1. 将桥接脚本放到以下路径，并确保可执行：",
        .step2HooksJson: "2. 将以下内容写入 ~/.cursor/hooks.json：",
        .step3RestartCursor: "3. 完全退出并重新启动 Cursor（Cmd+Q 后重新打开）。",
        .later: "稍后再说",
        .scriptExists: "脚本存在",
        .scriptExecutable: "脚本可执行",
        .hooksJsonExists: "hooks.json 存在",
        .requiredHooksComplete: "必需 Hook 齐全",
        .versionMatches: "版本匹配",
        .openCursorFolder: "打开 ~/.cursor 文件夹",
        .copyHooksJson: "复制 hooks.json",
        .installConfirmMessage: "将写入 ~/.cursor/hooks.json 和 ~/.cursor/hooks/liang-bridge.sh，并替换现有配置。是否继续？",
        .cursor: "Cursor",
        .ideSupportComingSoon: "%@ 支持即将到来",
        .claudeCode: "Claude Code",
        .codex: "Codex",
        .codebuddy: "CodeBuddy",
        .trae: "Trae",
        .aboutTitle: "MacOS Coding Agent 光晕助手",
        .aboutSubtitle: "通过不同光晕效果展示 AI 运行状态",
        .madeWithLove: "Made with ❤️",
        .versionFormat: "版本 %@",
        .changelog: "更新日志",
        .changelogPlaceholder: "未来版本更新内容将在此展示",
        .onboardingWindowTitle: "配置 Cursor Hooks",
        .welcomeTitle: "欢迎使用 Liang",
        .welcomeBody: "Liang 需要通过 Cursor Hooks 获取工作状态，才能在刘海处显示光晕提示。",
        .setupCompleteTitle: "配置完成",
        .setupCompleteBody: "Cursor Hooks 已配置完成。你可以稍后在设置中更改。",
        .cannotOpenEventsFile: "无法打开事件文件：%@",
        .eventsFileDecodeFailed: "事件文件解码失败",
        .cursorSetupMissingHooksJson: "未检测到 ~/.cursor/hooks.json",
        .cursorSetupInvalidHooksJson: "~/.cursor/hooks.json 内容格式不正确",
        .cursorSetupMissingBridgePath: "未解析到桥接脚本路径",
        .cursorSetupScriptMissing: "桥接脚本不存在：%@",
        .cursorSetupScriptNotExecutable: "桥接脚本没有可执行权限",
        .cursorSetupResourceMissing: "应用内未找到桥接脚本，请尝试手动安装。",
        .cursorSetupWriteFailed: "写入失败：%@",
        // Onboarding V2
        .onboardingConnectorTitle: "接入 Coding Agent",
        .onboardingConnectorSubtitle: "Liang 需要监听 Agent 的实时事件来驱动光晕。先完成 Cursor 配置即可启用全部效果。",
        .onboardingGlowTitle: "选择你的光晕",
        .onboardingGlowSubtitle: "每一种光晕都会随 AI 状态实时变化，按你的需要开启即可。",
        .onboardingNext: "下一步",
        .onboardingBack: "上一步",
        .onboardingStartUsing: "开始使用 Liang",
        .onboardingSkip: "暂时跳过",
        .onboardingSetupLater: "稍后再说",
        .onboardingCursorCardTitle: "Cursor",
        .onboardingCursorCardDesc: "Cursor 的 Hook 覆盖了所有关键状态，Liang 会在 Agent 一启动工作时立刻反应。",
        .onboardingOtherAgentsTitle: "其他 Agent",
        .onboardingOtherAgentsHint: "Codex CLI · CodeBuddy · Trae",
        .onboardingOtherComingSoon: "敬请期待…",
        .onboardingThanksTitle: "👋 感谢安装 Liang！",
        .onboardingThanksBody: "你可通过菜单中的“设置”更改相关设置项。\\n愿一个小小的光晕陪伴你独自 coding 的时光 ❤️",
        .onboardingThanksClose: "关闭",
        .onboardingNotchCardTitle: "刘海光晕",
        .onboardingNotchCardDesc: "彩色光环沿 MacBook 刘海轮廓流动，实时反映 AI 状态。",
        .onboardingCursorGlowCardTitle: "光标光晕",
        .onboardingCursorGlowCardDesc: "跟随鼠标光标的径向光晕，工作状态一眼可见。",
        .onboardingMenuBarCardTitle: "菜单栏状态色",
        .onboardingMenuBarCardDesc: "菜单栏图标随 AI 状态变色并轻微呼吸，无需打开窗口即可感知。",
        .onboardingNotAvailableMac: "该机型不支持刘海光晕",
        .onboardingStateBadgeIdle: "空闲",
        .onboardingStateBadgeProcessing: "进行中",
        .onboardingStateBadgeSuccess: "已完成",
        .onboardingPreviewLoopHint: "自动预览 · 循环播放",
        .onboardingPreviewActive: "效果展示中...",
        .onboardingCursorConnected: "已完成桥接",
        .onboardingCursorNotInstalledTitle: "未检测到 Cursor",
        .onboardingCursorNotInstalledMessage: "Liang 需要 Cursor 才能接收 Agent 事件。请先安装 Cursor；若已安装但未被检测到，仍可继续。",
        .onboardingCursorNotInstalledContinue: "仍要继续",
        .onboardingCursorNotInstalledDownload: "下载 Cursor",
        .glowTabGeneral: "通用",
        .glowTabNotch: "刘海",
        .glowTabCursor: "鼠标光标",
        .glowTabMenuBar: "菜单栏",
        .cursorSetupStatusConfigured: "已配置",
        .cursorSetupStatusMissing: "配置不完整（缺少文件）",
        .cursorSetupStatusPartial: "配置不完整（Hook 未全部注册）",
        .cursorSetupStatusNotConfigured: "未配置",
        .cursorSetupStatusChecking: "检测中",
        .enableClaudeCodeHooks: "启用 Claude Code Hooks",
        .claudeCodeHooksStatus: "Claude Code Hooks 状态",
        .eventsFileClaude: "事件文件：~/.liang/claude-events.jsonl",
        .claudeInstallDescription: "由 Liang 自动写入 ~/.claude/settings.json 和桥接脚本。不会读取或上传任何代码、prompt、文件内容。",
        .claudeInstallConfirmMessage: "将写入 ~/.claude/settings.json 和 ~/.claude/hooks/claude-bridge.sh，并保留你的其他 Claude Code 配置。是否继续？",
        .claudeSetupMissingSettingsJson: "未检测到 ~/.claude/settings.json",
        .claudeSetupInvalidSettingsJson: "~/.claude/settings.json 内容格式不正确",
        .onboardingClaudeCardDesc: "Claude Code 的 Hook 覆盖会话、工具与子代理状态，终端里的 Agent 一开工 Liang 就立刻反应。",
        .onboardingClaudeNotInstalledTitle: "未检测到 Claude Code",
        .onboardingClaudeNotInstalledMessage: "Liang 需要 Claude Code CLI 才能接收 Agent 事件。请先安装 Claude Code；若已安装但未被检测到，仍可继续。",
        .onboardingClaudeNotInstalledDownload: "安装 Claude Code"
    ]
}
