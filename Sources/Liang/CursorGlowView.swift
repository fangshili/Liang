import AppKit
import os

private let logger = Logger(subsystem: "com.liang", category: "CursorGlowView")

/// 光标跟随光晕的渲染视图（V3 完全弥散 aura）。
/// 用 Core Graphics 径向渐变生成一张带透明通道的位图，避免 CAShapeLayer 的硬中心和硬边。
final class CursorGlowView: NSView {
    private let glowLayer = CALayer()
    private var currentSize: CGFloat = 0
    private var currentColor: NSColor = .clear
    private var currentAlpha: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        glowLayer.masksToBounds = false
        layer?.addSublayer(glowLayer)
    }

    override func layout() {
        super.layout()
        glowLayer.frame = bounds
    }

    func apply(settings: GlowSettings, color: NSColor, animationMode: StateAppearance.AnimationMode) {
        let size = CGFloat(settings.cursorGlowSize)
        let alpha = CGFloat(settings.brightness)

        currentSize = size
        currentColor = color
        currentAlpha = alpha

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        if let image = makeGlowImage(size: size, color: color, alpha: alpha, scale: scale) {
            glowLayer.contents = image
            glowLayer.contentsScale = scale
        }

        applyAnimation(animationMode, alpha: alpha)
    }

    private func makeGlowImage(size: CGFloat, color: NSColor, alpha: CGFloat, scale: CGFloat) -> CGImage? {
        // 位图像素尺寸是点尺寸 × scale，保证 Retina 下不虚。
        let pixelSize = CGSize(width: size * 2 * scale, height: size * 2 * scale)
        let pixelRadius = (size / 2) * scale
        let center = CGPoint(x: pixelSize.width / 2, y: pixelSize.height / 2)

        guard let ctx = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let colors = [
            color.withAlphaComponent(alpha * 0.65).cgColor,
            color.withAlphaComponent(alpha * 0.18).cgColor,
            color.withAlphaComponent(0).cgColor
        ] as CFArray

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.35, 1.0]) else {
            return nil
        }

        ctx.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: pixelRadius,
            options: []
        )

        return ctx.makeImage()
    }

    private func applyAnimation(_ mode: StateAppearance.AnimationMode, alpha: CGFloat) {
        glowLayer.removeAllAnimations()

        let duration: TimeInterval
        switch mode {
        case .steady: return
        case .breathing: duration = 3.0
        case .slowPulse: duration = 1.8
        case .fastPulse: duration = 0.9
        case .urgentPulse: duration = 0.4
        }

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = Float(alpha * 0.45)
        opacityAnim.toValue = Float(alpha * 0.9)
        opacityAnim.duration = duration
        opacityAnim.autoreverses = true
        opacityAnim.repeatCount = .greatestFiniteMagnitude
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(opacityAnim, forKey: "pulse")
    }
}
