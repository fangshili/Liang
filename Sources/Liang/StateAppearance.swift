import AppKit

/// 每个状态对应的光晕外观：颜色和动画模式。
struct StateAppearance {
    let color: NSColor
    let mode: AnimationMode

    enum AnimationMode {
        case steady      // 静态
        case breathing   // 呼吸
        case slowPulse   // 慢速脉冲
        case fastPulse   // 快速脉冲
        case urgentPulse // 急促闪烁（错误）
    }

    static let defaultColors: [LiangState: NSColor] = [
        .idle: NSColor(hex: "#FF9229"),
        .processing: NSColor(hex: "#00BFFF"),
        .waiting: NSColor(hex: "#FFD700"),
        .success: NSColor(hex: "#00FF52"),
        .error: NSColor(hex: "#FF3B30"),
        .unknown: NSColor(hex: "#808080"),
        .disconnected: NSColor(hex: "#808080")
    ]
}

extension LiangState {
    /// 使用用户配置中的颜色（未配置则使用默认），动画模式固定。如果该状态被用户关闭，则返回 nil。
    func appearance(using settings: GlowSettings) -> StateAppearance? {
        guard settings.isStateGlowEnabled(self) else { return nil }
        let color = settings.stateColors[self] ?? StateAppearance.defaultColors[self] ?? NSColor(hex: "#808080")

        switch self {
        case .idle:
            return StateAppearance(color: color, mode: .breathing)
        case .processing:
            return StateAppearance(color: color, mode: .breathing)
        case .waiting:
            return StateAppearance(color: color, mode: .slowPulse)
        case .success:
            return StateAppearance(color: color, mode: .fastPulse)
        case .error:
            return StateAppearance(color: color, mode: .urgentPulse)
        case .unknown, .disconnected:
            return StateAppearance(color: color, mode: .steady)
        }
    }
}
