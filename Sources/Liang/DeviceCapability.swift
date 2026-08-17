import AppKit

/// 运行时检测当前 Mac 的硬件能力，特别是刘海屏。
/// 不维护机型名单，完全依赖 NSScreen 的 safeAreaInsets / auxiliaryTopLeftArea / auxiliaryTopRightArea。
enum DeviceCapability {
    /// 是否至少连接了一块带刘海的屏幕。
    static var hasNotchedScreen: Bool {
        NSScreen.screens.contains { $0.hasNotch }
    }

    /// 取所有刘海屏中刘海高度最大的那一块（通常就是内建主屏）。
    static var primaryNotchedScreen: NSScreen? {
        NSScreen.screens
            .filter { $0.hasNotch }
            .max { $0.notchHeight < $1.notchHeight }
    }

    /// 检测到的刘海尺寸。无刘海时返回 nil。
    static var notchMetrics: NotchMetrics? {
        guard let screen = primaryNotchedScreen else { return nil }
        return NotchMetrics(
            height: screen.notchHeight,
            width: screen.notchWidth,
            screenWidth: screen.frame.width
        )
    }

    struct NotchMetrics {
        let height: CGFloat
        let width: CGFloat
        let screenWidth: CGFloat
    }
}

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top > 0
            && auxiliaryTopLeftArea != nil
            && auxiliaryTopRightArea != nil
    }

    var notchHeight: CGFloat {
        hasNotch ? safeAreaInsets.top : 0
    }

    var notchWidth: CGFloat {
        guard hasNotch else { return 0 }
        let left = auxiliaryTopLeftArea?.width ?? 0
        let right = auxiliaryTopRightArea?.width ?? 0
        return max(frame.width - left - right, 80)
    }
}
