import Cocoa

final class GlowView: NSView {
    private let glowLayer = CAShapeLayer()
    private let accentLayer = CAShapeLayer()
    private var notchRect: NSRect = .zero
    private var hasNotch: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(accentLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(frame: NSRect, notchRect: NSRect, hasNotch: Bool) {
        self.notchRect = notchRect
        self.hasNotch = hasNotch
        glowLayer.frame = frame
        accentLayer.frame = frame
    }

    func apply(settings: GlowSettings, color: NSColor, animationMode: StateAppearance.AnimationMode) {
        let alpha = CGFloat(settings.brightness)
        let baseColor = color.withAlphaComponent(1.0)

        // 描边中心放在刘海边缘：向内 innerThickness，向外 outerThickness
        let totalWidth = settings.outerThickness + settings.innerThickness
        let centerInset = (settings.innerThickness - settings.outerThickness) / 2
        let pathRect = notchRect.insetBy(dx: -centerInset, dy: -centerInset)
        let cornerRadius = max(notchRect.height * settings.cornerRadiusScale - centerInset, 0)

        glowLayer.path = createNotchPath(rect: pathRect, cornerRadius: cornerRadius)
        glowLayer.fillColor = NSColor.clear.cgColor
        glowLayer.strokeColor = baseColor.withAlphaComponent(alpha).cgColor
        glowLayer.lineWidth = totalWidth
        glowLayer.lineCap = .round
        glowLayer.lineJoin = .round
        glowLayer.shadowColor = baseColor.withAlphaComponent(alpha).cgColor
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = settings.blurRadius
        glowLayer.shadowOpacity = Float(alpha)
        glowLayer.opacity = 1.0

        // accent line：紧贴刘海外边缘的细线高亮
        let accentPadding: CGFloat = 1
        let accentRect = notchRect.insetBy(dx: -accentPadding, dy: -accentPadding)
        let accentRadius = max(notchRect.height * settings.cornerRadiusScale - accentPadding, 0)
        accentLayer.path = createNotchPath(rect: accentRect, cornerRadius: accentRadius)
        accentLayer.fillColor = NSColor.clear.cgColor
        accentLayer.strokeColor = baseColor.withAlphaComponent(alpha).cgColor
        accentLayer.lineWidth = 2
        accentLayer.lineCap = .round
        accentLayer.lineJoin = .round
        accentLayer.shadowColor = baseColor.withAlphaComponent(alpha).cgColor
        accentLayer.shadowOffset = .zero
        accentLayer.shadowRadius = 2
        accentLayer.shadowOpacity = Float(alpha)
        accentLayer.opacity = 1.0

        glowLayer.removeAllAnimations()
        accentLayer.removeAllAnimations()

        switch animationMode {
        case .steady:
            // 静态：使用当前设置值，无动画。
            break
        case .breathing:
            if settings.breathingEnabled {
                addBreathingAnimation(
                    settings: settings,
                    color: baseColor,
                    alpha: alpha,
                    duration: 1.0 / settings.breathingSpeed,
                    minIntensity: 0.35
                )
            }
            // 关闭呼吸效果时保持静态亮度，不添加动画。
        case .slowPulse:
            addBreathingAnimation(
                settings: settings,
                color: baseColor,
                alpha: alpha,
                duration: 3.0,
                minIntensity: 0.2
            )
        case .fastPulse:
            addBreathingAnimation(
                settings: settings,
                color: baseColor,
                alpha: alpha,
                duration: 0.6,
                minIntensity: 0.15
            )
        case .urgentPulse:
            addBreathingAnimation(
                settings: settings,
                color: baseColor,
                alpha: alpha,
                duration: 0.3,
                minIntensity: 0.1
            )
        }
    }

    private func addBreathingAnimation(
        settings: GlowSettings,
        color: NSColor,
        alpha: CGFloat,
        duration: TimeInterval,
        minIntensity: CGFloat
    ) {
        let group = CAAnimationGroup()
        group.duration = duration
        group.autoreverses = true
        group.repeatCount = .greatestFiniteMagnitude
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let strokeColor = CABasicAnimation(keyPath: "strokeColor")
        strokeColor.fromValue = color.withAlphaComponent(alpha * minIntensity).cgColor
        strokeColor.toValue = color.withAlphaComponent(alpha).cgColor

        let shadowOpacity = CABasicAnimation(keyPath: "shadowOpacity")
        shadowOpacity.fromValue = Float(alpha * minIntensity)
        shadowOpacity.toValue = Float(alpha)

        let shadowRadius = CABasicAnimation(keyPath: "shadowRadius")
        shadowRadius.fromValue = settings.blurRadius * 0.7
        shadowRadius.toValue = settings.blurRadius * 1.3

        group.animations = [strokeColor, shadowOpacity, shadowRadius]
        glowLayer.add(group, forKey: "breathing")

        let accentGroup = CAAnimationGroup()
        accentGroup.duration = duration
        accentGroup.autoreverses = true
        accentGroup.repeatCount = .greatestFiniteMagnitude
        accentGroup.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let accentStrokeColor = CABasicAnimation(keyPath: "strokeColor")
        accentStrokeColor.fromValue = color.withAlphaComponent(alpha * minIntensity).cgColor
        accentStrokeColor.toValue = color.withAlphaComponent(alpha).cgColor

        let accentShadowOpacity = CABasicAnimation(keyPath: "shadowOpacity")
        accentShadowOpacity.fromValue = Float(alpha * minIntensity)
        accentShadowOpacity.toValue = Float(alpha)

        accentGroup.animations = [accentStrokeColor, accentShadowOpacity]
        accentLayer.add(accentGroup, forKey: "breathing")
    }

    private func createNotchPath(rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let r = min(cornerRadius, rect.width / 2, rect.height / 2)

        // 刘海路径：顶部是屏幕直边，两侧直边，底部两个圆角
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: 0,
            endAngle: -.pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: -.pi / 2,
            endAngle: -.pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
