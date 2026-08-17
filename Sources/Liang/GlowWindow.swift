import Cocoa
import os

private let logger = Logger(subsystem: "com.liang", category: "GlowWindow")

final class GlowWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .init(NSWindow.Level.mainMenu.rawValue + 1)
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.contentView = GlowView()
    }

    func updateFrame() {
        logger.debug("updateFrame called. screens=\(NSScreen.screens.map { $0.localizedName })")
        guard let screen = notchedScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            logger.debug("no screen available")
            return
        }

        let frame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let hasNotch = safeTop > 0

        logger.debug("selected screen: \(screen.localizedName), frame=\(String(describing: frame)), safeTop=\(safeTop), auxLeft=\(String(describing: screen.auxiliaryTopLeftArea)), auxRight=\(String(describing: screen.auxiliaryTopRightArea))")

        let settings = GlowSettings.shared
        let notchInset = settings.notchInset
        let horizontalOffset = settings.horizontalOffset

        // 刘海/菜单栏区域高度：有刘海时用安全区高度，否则用菜单栏高度。
        let menuBarHeight: CGFloat = screen.frame.maxY - screen.visibleFrame.maxY
        let glowHeight: CGFloat = max(menuBarHeight, safeTop) + 4

        // 窗口宽度覆盖整个屏幕宽度，确保刘海两侧都有光晕。
        let windowFrame = CGRect(
            x: frame.origin.x,
            y: frame.maxY - glowHeight,
            width: frame.width,
            height: glowHeight
        )

        self.setFrame(windowFrame, display: true)

        // 估算刘海/顶部区域尺寸。
        let notchHeight = hasNotch ? safeTop : menuBarHeight
        let notchWidth: CGFloat
        if hasNotch {
            let leftAux = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightAux = screen.auxiliaryTopRightArea?.width ?? 0
            notchWidth = max(frame.width - leftAux - rightAux, 80)
        } else {
            notchWidth = min(120, frame.width * 0.3)
        }

        let notchRect = CGRect(
            x: frame.midX - notchWidth / 2 + horizontalOffset,
            y: frame.maxY - notchHeight - notchInset,
            width: notchWidth,
            height: notchHeight
        )

        if let glowView = self.contentView as? GlowView {
            // 把屏幕坐标转换为 contentView 本地坐标，否则 layer 会被画到窗口外面。
            let localBounds = glowView.bounds
            let localNotchRect = CGRect(
                x: notchRect.minX - windowFrame.minX,
                y: localBounds.height - notchHeight - notchInset,
                width: notchRect.width,
                height: notchRect.height
            )
            glowView.update(frame: localBounds, notchRect: localNotchRect, hasNotch: hasNotch)
            logger.debug("hasNotch=\(hasNotch), localBounds=\(String(describing: localBounds)), localNotchRect=\(String(describing: localNotchRect))")
        } else {
            logger.debug("hasNotch=\(hasNotch), windowFrame=\(String(describing: windowFrame)), notchRect=\(String(describing: notchRect))")
        }
    }

    func apply(settings: GlowSettings, color: NSColor, animationMode: StateAppearance.AnimationMode) {
        (contentView as? GlowView)?.apply(settings: settings, color: color, animationMode: animationMode)
    }
}

private extension NSScreen {
    /// 优先返回带刘海的内建屏幕。
    var isNotched: Bool {
        return safeAreaInsets.top > 0
    }
}

private func notchedScreen() -> NSScreen? {
    return NSScreen.screens.first { $0.isNotched }
}
