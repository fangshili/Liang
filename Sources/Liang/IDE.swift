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

    /// 任务列表来源图标（template image，可用 contentTintColor 着色）。
    /// 新增 IDE 时在此补一个资源名 + 资源文件即可。
    var iconImage: NSImage? {
        let name: String
        switch self {
        case .cursor: name = "cursor-icon"
        case .claudeCode: name = "claude-icon"
        default: return nil
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}
