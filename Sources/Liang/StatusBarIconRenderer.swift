import AppKit

/// 绘制菜单栏光晕小球图标。
/// 关闭状态色时显示柔和的白色静态光晕；开启时根据状态色和动画模式绘制带呼吸/脉冲效果的小球。
enum StatusBarIconRenderer {
    static let size = NSSize(width: 18, height: 18)

    /// 仅用于 onboarding 预览：强制让菜单栏图标显示状态色，不影响用户的 `menuBarStateColorEnabled` 设置。
    static var previewForceShowMenuBarColor: Bool = false

    /// 绘制缺省的白色静态光晕小球。
    static func renderDefault() -> NSImage {
        render(color: NSColor.white, intensity: 1.0)
    }

    /// 绘制指定状态对应的光晕小球，动画强度由调用者根据当前时间和动画模式计算。
    static func render(state: LiangState, settings: GlowSettings, intensity: CGFloat) -> NSImage {
        let color: NSColor
        if (settings.menuBarStateColorEnabled || previewForceShowMenuBarColor),
           settings.isStateGlowEnabled(state),
           let stateColor = settings.stateColors[state] ?? StateAppearance.defaultColors[state] {
            color = stateColor
        } else {
            color = NSColor.white
        }
        return render(color: color, intensity: intensity)
    }

    /// 核心绘制：径向渐变光晕小球。
    static func render(color: NSColor, intensity: CGFloat) -> NSImage {
        let clampedIntensity = max(0.15, min(1.0, intensity))
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let endRadius = rect.width * 0.55

            let coreColor = color.withAlphaComponent(0.95 * clampedIntensity).cgColor
            let midColor = color.withAlphaComponent(0.45 * clampedIntensity).cgColor
            let edgeColor = color.withAlphaComponent(0.0).cgColor

            let colors = [coreColor, midColor, edgeColor] as CFArray
            let locations: [CGFloat] = [0.0, 0.45, 1.0]

            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return false }

            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: endRadius,
                options: .drawsBeforeStartLocation
            )

            return true
        }
        image.isTemplate = false
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    /// 根据状态动画模式、当前时间和设置计算动画强度（0..1）。
    static func intensity(for state: LiangState, settings: GlowSettings) -> CGFloat {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard !reduceMotion && !lowPower else { return 1.0 }

        guard (settings.menuBarStateColorEnabled || previewForceShowMenuBarColor),
              settings.isStateGlowEnabled(state),
              let appearance = state.appearance(using: settings) else {
            return 1.0
        }

        let t = Date().timeIntervalSinceReferenceDate

        // 与 GlowView/CursorGlowView 的 CAAnimation 周期保持一致：
        // duration 是半个周期（autoreverses  true），完整周期 = duration * 2。
        func sineIntensity(fullCycle: TimeInterval, minIntensity: CGFloat) -> CGFloat {
            let phase = sin(2 * .pi * t / fullCycle)
            return minIntensity + (1.0 - minIntensity) * (phase + 1) / 2
        }

        switch appearance.mode {
        case .steady:
            return 1.0

        case .breathing:
            let speed = (settings.menuBarStateColorEnabled || previewForceShowMenuBarColor) ? settings.menuBarBreathingSpeed : 0.6
            let fullCycle = (1.0 / speed) * 2
            return sineIntensity(fullCycle: fullCycle, minIntensity: 0.35)

        case .slowPulse:
            return sineIntensity(fullCycle: 6.0, minIntensity: 0.2)

        case .fastPulse:
            return sineIntensity(fullCycle: 1.2, minIntensity: 0.15)

        case .urgentPulse:
            return sineIntensity(fullCycle: 0.6, minIntensity: 0.1)
        }
    }
}
