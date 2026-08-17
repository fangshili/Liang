import AppKit
import os

private let logger = Logger(subsystem: "com.liang", category: "CursorLabelWindow")

extension LiangState {
    /// 光标右侧提示语；仅在有明确用户可感知状态时才显示。
    var cursorLabelText: String? {
        // 光标旁状态标签固定显示英文，不跟随应用语言切换。
        switch self {
        case .processing: return "Processing"
        case .success: return "Done"
        case .error: return "Fail"
        case .waiting: return "Waiting"
        default: return nil
        }
    }
}

/// 跟随光标右侧的小型状态提示标签。
/// 圆角 pill 形状，背景跟随状态光晕颜色，白字加深色投影以保证可读性。
final class CursorLabelWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")
    private let container = NSView()

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
        level = .init(NSWindow.Level.floating.rawValue)
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = container

        container.wantsLayer = true
        container.layer?.masksToBounds = false

        label.alignment = .center
        label.isBordered = false
        label.backgroundColor = .clear
        label.isEditable = false
        label.isSelectable = false
        container.addSubview(label)
    }

    func apply(state: LiangState, color: NSColor, enabled: Bool) {
        guard enabled, let text = state.cursorLabelText else {
            orderOut(nil)
            return
        }

        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
                .foregroundColor: NSColor.white,
                .shadow: textDropShadow()
            ]
        )
        label.sizeToFit()

        let padding = NSSize(width: 7, height: 3)
        let size = NSSize(
            width: label.frame.width + padding.width * 2,
            height: label.frame.height + padding.height * 2
        )
        setContentSize(size)

        container.layer?.backgroundColor = color.withAlphaComponent(0.75).cgColor
        container.layer?.cornerRadius = size.height / 2
        container.layer?.shadowColor = color.cgColor
        container.layer?.shadowOpacity = 0.45
        container.layer?.shadowRadius = 4
        container.layer?.shadowOffset = .zero

        label.frame = CGRect(
            x: padding.width,
            y: padding.height,
            width: label.frame.width,
            height: label.frame.height
        )

        orderFront(nil)
    }

    private func textDropShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2.0
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        return shadow
    }
}
