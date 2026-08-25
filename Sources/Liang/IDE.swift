import Foundation
import AppKit

/// 支持的 IDE 来源。目前仅 Cursor 接入，其余为预留。
enum IDE: String, CaseIterable, Identifiable, Codable {
    case cursor = "Cursor"
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case codeBuddy = "CodeBuddy"
    case trae = "Trae"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: return I18n.shared.string(.cursor)
        case .claudeCode: return I18n.shared.string(.claudeCode)
        case .codex: return I18n.shared.string(.codex)
        case .codeBuddy: return I18n.shared.string(.codebuddy)
        case .trae: return I18n.shared.string(.trae)
        }
    }
}

extension IDE {
    /// 桥接脚本 `source` 字段对应的取值。
    var sourceValue: String {
        switch self {
        case .cursor: return "cursor"
        case .claudeCode: return "claude_code"
        default: return rawValue.lowercased()
        }
    }

    /// 从桥接脚本的 `source` 字段还原 IDE。
    static func fromSource(_ source: String) -> IDE {
        IDE.allCases.first { $0.sourceValue == source } ?? .cursor
    }

    /// 任务列表来源图标（template image，单色 tint）。
    var iconImage: NSImage? {
        switch self {
        case .cursor: return Self.loadIcon("cursor-icon")
        case .claudeCode: return Self.loadIcon("claude-icon")
        case .codex: return Self.loadIcon("codex-task-icon")
        case .codeBuddy: return Self.loadIcon("codebuddy-task-icon")
        default: return nil
        }
    }

    /// onboarding 卡片图标：cursor/claude 为 template（可 tint），codex/codebuddy 为彩色原图。
    var onboardingIconImage: NSImage? {
        switch self {
        case .cursor: return Self.loadIcon("cursor-icon")
        case .claudeCode: return Self.loadIcon("claude-icon")
        case .codex: return Self.loadColoredIcon("codex-onboarding-icon")
        case .codeBuddy: return Self.loadColoredIcon("codebuddy-onboarding-icon")
        default: return nil
        }
    }

    private static func loadIcon(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    /// 加载彩色图标（非 template，保留原始颜色）。
    private static func loadColoredIcon(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
