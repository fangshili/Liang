import Foundation
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "GlowSettings")

/// 用户配置：光晕几何、动画、功能开关、状态颜色和状态引擎参数。
/// T7 责任：持久化、恢复默认、异常时回退到安全默认值。
final class GlowSettings: ObservableObject, Codable {
    static let shared = GlowSettings()

    @Published var glowEnabled: Bool = true
    @Published var cursorHooksEnabled: Bool = true
    @Published var menuBarStateColorEnabled: Bool = true
    @Published var menuBarBreathingSpeed: Double = 0.85

    @Published var brightness: Double = 1.0
    @Published var blurRadius: Double = 15.0
    @Published var outerThickness: Double = 1.0
    @Published var innerThickness: Double = 0.0
    @Published var notchInset: Double = 0.0
    @Published var horizontalOffset: Double = 0.0
    @Published var cornerRadiusScale: Double = 0.36

    @Published var breathingEnabled: Bool = true
    @Published var breathingSpeed: Double = 0.70

    /// 每个状态对应的颜色；未配置的状态使用 StateAppearance.defaultColors。
    @Published var stateColors: [LiangState: NSColor] = StateAppearance.defaultColors

    /// 状态引擎参数，统一持久化。
    @Published var processingTimeout: Double = 60
    @Published var successMaxDuration: Double = 20
    @Published var waitingTimeoutEnabled: Bool = false
    @Published var deduplicationWindow: Double = 1.0

    /// 刘海展开面板开关。
    @Published var notchExpansionEnabled: Bool = true

    /// 光标跟随光晕开关与外观。
    @Published var cursorGlowEnabled: Bool = true
    @Published var cursorLabelEnabled: Bool = true
    @Published var cursorGlowSize: Double = 23
    @Published var cursorGlowOffsetX: Double = 36
    @Published var cursorGlowOffsetY: Double = -32

    /// 每个状态是否显示光晕。未在字典中的状态默认启用。
    @Published var stateGlowEnabled: [LiangState: Bool] = [:]

    /// 各 IDE 是否启用。T9 阶段仅 Cursor 生效，其余为预留。
    @Published var ideEnabled: [IDE: Bool] = [.cursor: true]

    /// 是否已完成首次启动的 Cursor 配置引导。
    @Published var hasCompletedCursorSetup: Bool = false

    /// 是否已完成首次启动的 Claude Code 配置引导。
    @Published var hasCompletedClaudeSetup: Bool = false

    /// 是否已完成首次启动的 Onboarding 整体引导（两步流程）。
    /// 与 `hasCompletedCursorSetup` 区别：后者只关心 Cursor 这一项，前者要求用户走完整个引导流程。
    @Published var hasCompletedOnboarding: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private static let userDefaultsKey = "com.liang.settings.v1"

    private enum CodingKeys: String, CodingKey {
        case glowEnabled, cursorHooksEnabled, menuBarStateColorEnabled, menuBarBreathingSpeed
        case brightness, blurRadius, outerThickness, innerThickness
        case notchInset, horizontalOffset, cornerRadiusScale
        case breathingEnabled, breathingSpeed
        case stateColors, stateGlowEnabled
        case processingTimeout, successMaxDuration, waitingTimeoutEnabled, deduplicationWindow
        case notchExpansionEnabled, cursorGlowEnabled, cursorLabelEnabled, cursorGlowSize, cursorGlowOffsetX, cursorGlowOffsetY
        case ideEnabled
        case hasCompletedCursorSetup
        case hasCompletedClaudeSetup
        case hasCompletedOnboarding
    }

    /// 仅供内部构造默认值使用，不会触发持久化。
    init(defaults: Bool) {
        if !defaults {
            let hadSavedData = load()
            setupAutosave()
            if !hadSavedData {
                applyFactoryDefaultsForCurrentDevice()
            }
        }
    }

    convenience init() {
        self.init(defaults: false)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        glowEnabled = try container.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? true
        cursorHooksEnabled = try container.decodeIfPresent(Bool.self, forKey: .cursorHooksEnabled) ?? true
        menuBarStateColorEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarStateColorEnabled) ?? true
        menuBarBreathingSpeed = try container.decodeIfPresent(Double.self, forKey: .menuBarBreathingSpeed) ?? 0.85

        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 1.0
        blurRadius = try container.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 15.0
        outerThickness = try container.decodeIfPresent(Double.self, forKey: .outerThickness) ?? 1.0
        innerThickness = try container.decodeIfPresent(Double.self, forKey: .innerThickness) ?? 0.0
        notchInset = try container.decodeIfPresent(Double.self, forKey: .notchInset) ?? 0.0
        horizontalOffset = try container.decodeIfPresent(Double.self, forKey: .horizontalOffset) ?? 0.0
        cornerRadiusScale = try container.decodeIfPresent(Double.self, forKey: .cornerRadiusScale) ?? 0.36

        breathingEnabled = try container.decodeIfPresent(Bool.self, forKey: .breathingEnabled) ?? true
        breathingSpeed = try container.decodeIfPresent(Double.self, forKey: .breathingSpeed) ?? 0.70

        let hexColors = try container.decodeIfPresent([String: String].self, forKey: .stateColors) ?? [:]
        stateColors = [:]
        for (key, hex) in hexColors {
            guard let state = LiangState(rawValue: key) ?? LiangState.legacy(key) else { continue }
            stateColors[state] = NSColor(hex: hex)
        }

        processingTimeout = try container.decodeIfPresent(Double.self, forKey: .processingTimeout) ?? 60
        successMaxDuration = try container.decodeIfPresent(Double.self, forKey: .successMaxDuration) ?? 20
        waitingTimeoutEnabled = try container.decodeIfPresent(Bool.self, forKey: .waitingTimeoutEnabled) ?? false
        deduplicationWindow = try container.decodeIfPresent(Double.self, forKey: .deduplicationWindow) ?? 1.0

        notchExpansionEnabled = try container.decodeIfPresent(Bool.self, forKey: .notchExpansionEnabled) ?? true
        cursorGlowEnabled = try container.decodeIfPresent(Bool.self, forKey: .cursorGlowEnabled) ?? true
        cursorLabelEnabled = try container.decodeIfPresent(Bool.self, forKey: .cursorLabelEnabled) ?? true
        cursorGlowSize = try container.decodeIfPresent(Double.self, forKey: .cursorGlowSize) ?? 23
        cursorGlowOffsetX = try container.decodeIfPresent(Double.self, forKey: .cursorGlowOffsetX) ?? 36
        cursorGlowOffsetY = try container.decodeIfPresent(Double.self, forKey: .cursorGlowOffsetY) ?? -32

        let enabledFlags = try container.decodeIfPresent([String: Bool].self, forKey: .stateGlowEnabled) ?? [:]
        stateGlowEnabled = [:]
        for (key, enabled) in enabledFlags {
            guard let state = LiangState(rawValue: key) ?? LiangState.legacy(key) else { continue }
            stateGlowEnabled[state] = enabled
        }

        let ideFlags = try container.decodeIfPresent([String: Bool].self, forKey: .ideEnabled) ?? [:]
        ideEnabled = [:]
        for (key, enabled) in ideFlags {
            guard let ide = IDE(rawValue: key) else { continue }
            ideEnabled[ide] = enabled
        }
        if ideEnabled[.cursor] == nil {
            ideEnabled[.cursor] = true
        }

        hasCompletedCursorSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedCursorSetup) ?? false
        hasCompletedClaudeSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedClaudeSetup) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false

        setupAutosave()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(glowEnabled, forKey: .glowEnabled)
        try container.encode(cursorHooksEnabled, forKey: .cursorHooksEnabled)
        try container.encode(menuBarStateColorEnabled, forKey: .menuBarStateColorEnabled)
        try container.encode(menuBarBreathingSpeed, forKey: .menuBarBreathingSpeed)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(blurRadius, forKey: .blurRadius)
        try container.encode(outerThickness, forKey: .outerThickness)
        try container.encode(innerThickness, forKey: .innerThickness)
        try container.encode(notchInset, forKey: .notchInset)
        try container.encode(horizontalOffset, forKey: .horizontalOffset)
        try container.encode(cornerRadiusScale, forKey: .cornerRadiusScale)
        try container.encode(breathingEnabled, forKey: .breathingEnabled)
        try container.encode(breathingSpeed, forKey: .breathingSpeed)
        var hexColors: [String: String] = [:]
        for (state, color) in stateColors {
            hexColors[state.rawValue] = color.toHex()
        }
        try container.encode(hexColors, forKey: .stateColors)
        try container.encode(processingTimeout, forKey: .processingTimeout)
        try container.encode(successMaxDuration, forKey: .successMaxDuration)
        try container.encode(waitingTimeoutEnabled, forKey: .waitingTimeoutEnabled)
        try container.encode(deduplicationWindow, forKey: .deduplicationWindow)

        try container.encode(notchExpansionEnabled, forKey: .notchExpansionEnabled)
        try container.encode(cursorGlowEnabled, forKey: .cursorGlowEnabled)
        try container.encode(cursorLabelEnabled, forKey: .cursorLabelEnabled)
        try container.encode(cursorGlowSize, forKey: .cursorGlowSize)
        try container.encode(cursorGlowOffsetX, forKey: .cursorGlowOffsetX)
        try container.encode(cursorGlowOffsetY, forKey: .cursorGlowOffsetY)

        var enabledFlags: [String: Bool] = [:]
        for (state, enabled) in stateGlowEnabled {
            enabledFlags[state.rawValue] = enabled
        }
        try container.encode(enabledFlags, forKey: .stateGlowEnabled)

        var ideFlags: [String: Bool] = [:]
        for (ide, enabled) in ideEnabled {
            ideFlags[ide.rawValue] = enabled
        }
        try container.encode(ideFlags, forKey: .ideEnabled)

        try container.encode(hasCompletedCursorSetup, forKey: .hasCompletedCursorSetup)
        try container.encode(hasCompletedClaudeSetup, forKey: .hasCompletedClaudeSetup)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }

    /// 恢复为硬编码的安全默认值。
    func restoreDefaults() {
        let defaults = GlowSettings(defaults: true)
        glowEnabled = defaults.glowEnabled
        cursorHooksEnabled = defaults.cursorHooksEnabled
        menuBarStateColorEnabled = defaults.menuBarStateColorEnabled
        menuBarBreathingSpeed = defaults.menuBarBreathingSpeed
        brightness = defaults.brightness
        blurRadius = defaults.blurRadius
        outerThickness = defaults.outerThickness
        innerThickness = defaults.innerThickness
        notchInset = defaults.notchInset
        horizontalOffset = defaults.horizontalOffset
        cornerRadiusScale = defaults.cornerRadiusScale
        breathingEnabled = defaults.breathingEnabled
        breathingSpeed = defaults.breathingSpeed
        stateColors = defaults.stateColors
        stateGlowEnabled = defaults.stateGlowEnabled
        processingTimeout = defaults.processingTimeout
        successMaxDuration = defaults.successMaxDuration
        waitingTimeoutEnabled = defaults.waitingTimeoutEnabled
        deduplicationWindow = defaults.deduplicationWindow
        notchExpansionEnabled = defaults.notchExpansionEnabled
        cursorGlowEnabled = defaults.cursorGlowEnabled
        cursorLabelEnabled = defaults.cursorLabelEnabled
        cursorGlowSize = defaults.cursorGlowSize
        cursorGlowOffsetX = defaults.cursorGlowOffsetX
        cursorGlowOffsetY = defaults.cursorGlowOffsetY
        ideEnabled = defaults.ideEnabled
        hasCompletedCursorSetup = defaults.hasCompletedCursorSetup
        hasCompletedClaudeSetup = defaults.hasCompletedClaudeSetup
        hasCompletedOnboarding = defaults.hasCompletedOnboarding
    }

    func restoreGeneralGlowDefaults() {
        let defaults = GlowSettings(defaults: true)
        brightness = defaults.brightness
        blurRadius = defaults.blurRadius
    }

    func restoreNotchDefaults() {
        let defaults = GlowSettings(defaults: true)
        glowEnabled = defaults.glowEnabled
        outerThickness = defaults.outerThickness
        innerThickness = defaults.innerThickness
        notchInset = defaults.notchInset
        horizontalOffset = defaults.horizontalOffset
        cornerRadiusScale = defaults.cornerRadiusScale
        breathingEnabled = defaults.breathingEnabled
        breathingSpeed = defaults.breathingSpeed
        notchExpansionEnabled = defaults.notchExpansionEnabled
    }

    func restoreCursorGlowDefaults() {
        let defaults = GlowSettings(defaults: true)
        cursorGlowEnabled = defaults.cursorGlowEnabled
        cursorLabelEnabled = defaults.cursorLabelEnabled
        cursorGlowSize = defaults.cursorGlowSize
        cursorGlowOffsetX = defaults.cursorGlowOffsetX
        cursorGlowOffsetY = defaults.cursorGlowOffsetY
    }

    func restoreMenuBarDefaults() {
        let defaults = GlowSettings(defaults: true)
        menuBarStateColorEnabled = defaults.menuBarStateColorEnabled
        menuBarBreathingSpeed = defaults.menuBarBreathingSpeed
    }

    @discardableResult
    private func load() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) else { return false }
        do {
            let loaded = try JSONDecoder().decode(GlowSettings.self, from: data)
            glowEnabled = loaded.glowEnabled
            cursorHooksEnabled = loaded.cursorHooksEnabled
            menuBarStateColorEnabled = loaded.menuBarStateColorEnabled
            menuBarBreathingSpeed = loaded.menuBarBreathingSpeed
            brightness = loaded.brightness
            blurRadius = loaded.blurRadius
            outerThickness = loaded.outerThickness
            innerThickness = loaded.innerThickness
            notchInset = loaded.notchInset
            horizontalOffset = loaded.horizontalOffset
            cornerRadiusScale = loaded.cornerRadiusScale
            breathingEnabled = loaded.breathingEnabled
            breathingSpeed = loaded.breathingSpeed
            if !loaded.stateColors.isEmpty {
                stateColors = loaded.stateColors
            }
            stateGlowEnabled = loaded.stateGlowEnabled
            processingTimeout = loaded.processingTimeout
            successMaxDuration = loaded.successMaxDuration
            waitingTimeoutEnabled = loaded.waitingTimeoutEnabled
            deduplicationWindow = loaded.deduplicationWindow
            notchExpansionEnabled = loaded.notchExpansionEnabled
            cursorGlowEnabled = loaded.cursorGlowEnabled
            cursorLabelEnabled = loaded.cursorLabelEnabled
            cursorGlowSize = loaded.cursorGlowSize
            cursorGlowOffsetX = loaded.cursorGlowOffsetX
            cursorGlowOffsetY = loaded.cursorGlowOffsetY
            ideEnabled = loaded.ideEnabled
            hasCompletedCursorSetup = loaded.hasCompletedCursorSetup
            hasCompletedClaudeSetup = loaded.hasCompletedClaudeSetup
            hasCompletedOnboarding = loaded.hasCompletedOnboarding
            return true
        } catch {
            logger.error("Failed to load settings, falling back to defaults: \(error.localizedDescription)")
            return false
        }
    }

    /// 首次启动且无已保存配置时，根据当前设备是否有刘海设置更合理的默认值。
    private func applyFactoryDefaultsForCurrentDevice() {
        if DeviceCapability.hasNotchedScreen {
            applyNotchedDefaults()
        } else {
            applyNonNotchedDefaults()
        }
    }

    private func applyNotchedDefaults() {
        // 首次打开时所有光晕默认关闭，由用户在 onboarding Step 2 中自行开启。
        glowEnabled = false
        cursorGlowEnabled = false
        menuBarStateColorEnabled = false

        // 基准值来自 16" MacBook Pro 2023 的满意参数。
        // 若检测到其它刘海高度（如 14"），按比例缩放厚度与模糊。
        let referenceHeight: CGFloat = 38.0
        let detectedHeight = DeviceCapability.notchMetrics?.height ?? referenceHeight
        let scale = max(0.5, min(1.5, Double(detectedHeight / referenceHeight)))

        blurRadius = 15.0 * scale
        outerThickness = 1.0 * scale
        innerThickness = 0.0 * scale
        // 水平偏移、刘海内缩、圆角比例保持基准值。
        notchInset = 0.0
        horizontalOffset = 0.0
        cornerRadiusScale = 0.36

        logger.info("Applied notched screen defaults: notch height \(detectedHeight)pt, scale \(scale)")
    }

    private func applyNonNotchedDefaults() {
        glowEnabled = false
        cursorGlowEnabled = true
        menuBarStateColorEnabled = true

        logger.info("Applied non-notched screen defaults")
    }

    /// 某个状态是否启用光晕。未设置时默认启用。
    func isStateGlowEnabled(_ state: LiangState) -> Bool {
        stateGlowEnabled[state] ?? true
    }

    /// 设置某个状态的光晕开关。
    func setStateGlowEnabled(_ state: LiangState, enabled: Bool) {
        stateGlowEnabled[state] = enabled
    }

    /// 某个 IDE 是否启用。Cursor 使用独立的 `cursorHooksEnabled`，其余 IDE 使用 `ideEnabled` 字典。
    func isIDEEnabled(_ ide: IDE) -> Bool {
        if ide == .cursor {
            return cursorHooksEnabled
        }
        return ideEnabled[ide] ?? false
    }

    /// 设置某个 IDE 的启用开关。Cursor 同步到 `cursorHooksEnabled`。
    func setIDEEnabled(_ ide: IDE, enabled: Bool) {
        if ide == .cursor {
            cursorHooksEnabled = enabled
        } else {
            ideEnabled[ide] = enabled
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } catch {
            logger.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    /// 防抖自动保存：配置变化后 0.3 秒写入 UserDefaults。
    private func setupAutosave() {
        objectWillChange
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }
}
