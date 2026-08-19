import AppKit
import Combine

/// 任务列表单行视图：状态点 + 来源图标 + 标题 + 时间。
final class TaskRowView: NSView {
    private let dotLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let timeField = NSTextField(labelWithString: "")
    private var cancellables = Set<AnyCancellable>()

    var task: TaskItem? {
        didSet { update() }
    }

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

        // 状态点
        dotLayer.fillColor = NSColor.white.cgColor
        dotLayer.strokeColor = NSColor.clear.cgColor
        layer?.addSublayer(dotLayer)

        // 来源图标
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor(white: 0.62, alpha: 1.0)
        addSubview(iconView)

        // 标题
        titleField.textColor = NSColor(white: 0.95, alpha: 1.0)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .left
        titleField.isEditable = false
        titleField.isBordered = false
        titleField.backgroundColor = .clear
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        // 时间
        timeField.textColor = NSColor(white: 0.55, alpha: 1.0)
        timeField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        timeField.alignment = .right
        timeField.isEditable = false
        timeField.isBordered = false
        timeField.backgroundColor = .clear
        timeField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeField)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 58),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(equalTo: timeField.leadingAnchor, constant: -12),

            timeField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            timeField.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeField.widthAnchor.constraint(equalToConstant: 56)
        ])

        GlowSettings.shared.$stateColors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
    }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 8
        let dotY = (bounds.height - dotSize) / 2
        dotLayer.frame = CGRect(x: 22, y: dotY, width: dotSize, height: dotSize)
        dotLayer.path = CGPath(ellipseIn: dotLayer.bounds, transform: nil)

        let iconSize: CGFloat = 14
        let iconY = (bounds.height - iconSize) / 2
        iconView.frame = CGRect(x: 38, y: iconY, width: iconSize, height: iconSize)
    }

    private func update() {
        guard let task = task else {
            titleField.stringValue = ""
            timeField.stringValue = ""
            dotLayer.removeAllAnimations()
            return
        }

        titleField.stringValue = task.title
        timeField.stringValue = Self.formatTime(task.updatedAt)
        iconView.image = IDE.fromSource(task.source).iconImage

        let appearance = task.state.appearance(using: GlowSettings.shared)
        dotLayer.fillColor = (appearance?.color ?? NSColor.white).cgColor
        dotLayer.removeAllAnimations()

        guard let mode = appearance?.mode else { return }
        switch mode {
        case .breathing:
            dotLayer.add(breathingAnimation(), forKey: "breathing")
        case .slowPulse:
            dotLayer.add(pulseAnimation(duration: 6), forKey: "pulse")
        case .fastPulse:
            dotLayer.add(pulseAnimation(duration: 1.2), forKey: "pulse")
        case .urgentPulse:
            dotLayer.add(urgentPulseAnimation(), forKey: "urgent")
        case .steady:
            break
        }
    }

    private func breathingAnimation() -> CAAnimation {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [1.0, 0.45, 1.0]
        anim.keyTimes = [0, 0.5, 1]
        let speed = GlowSettings.shared.breathingSpeed
        anim.duration = speed > 0 ? 1.0 / speed * 2 : 2.0
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return anim
    }

    private func pulseAnimation(duration: TimeInterval) -> CAAnimation {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [1.0, 0.3, 1.0]
        anim.keyTimes = [0, 0.5, 1]
        anim.duration = duration
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return anim
    }

    private func urgentPulseAnimation() -> CAAnimation {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [1.0, 0.2, 1.0, 0.2, 1.0]
        anim.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        anim.duration = 0.6
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        return anim
    }

    private static func formatTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return I18n.shared.string(.justNow) }
        if interval < 3600 { return I18n.shared.string(.minutesAgo, Int(interval / 60)) }
        if interval < 86400 { return I18n.shared.string(.hoursAgo, Int(interval / 3600)) }
        return I18n.shared.string(.daysAgo, Int(interval / 86400))
    }
}
