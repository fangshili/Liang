import AppKit

/// 光标跟随光晕的透明无边框窗口。
final class CursorGlowWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 悬浮在正常窗口之上，但不要高过菜单栏/弹窗。
        level = .init(NSWindow.Level.floating.rawValue)
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = CursorGlowView()
    }

    func apply(settings: GlowSettings, color: NSColor, animationMode: StateAppearance.AnimationMode) {
        (contentView as? CursorGlowView)?.apply(settings: settings, color: color, animationMode: animationMode)
    }
}
