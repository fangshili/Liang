import Foundation

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
