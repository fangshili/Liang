import Foundation

enum LiangState: String, CaseIterable {
    case idle
    case processing
    case waiting
    case success
    case error
    case unknown
    case disconnected
}

extension LiangState {
    /// 任务列表排序优先级：进行中的状态排在最前，方便用户一眼看到当前活跃任务。
    var priority: Int {
        switch self {
        case .processing: return 6
        case .waiting: return 5
        case .error: return 4
        case .success: return 3
        case .unknown: return 2
        case .disconnected: return 1
        case .idle: return 0
        }
    }

    var isTransient: Bool {
        self == .success
    }

    /// 面向用户的状态名称，随当前语言切换。
    var localizedName: String {
        switch self {
        case .idle: return I18n.shared.string(.stateIdle)
        case .processing: return I18n.shared.string(.stateProcessing)
        case .waiting: return I18n.shared.string(.stateWaiting)
        case .success: return I18n.shared.string(.stateSuccess)
        case .error: return I18n.shared.string(.stateError)
        case .unknown: return I18n.shared.string(.stateUnknown)
        case .disconnected: return I18n.shared.string(.stateDisconnected)
        }
    }

    /// 兼容旧配置中使用的中文 rawValue key。
    static func legacy(_ rawValue: String) -> LiangState? {
        switch rawValue {
        case "空闲": return .idle
        case "处理中": return .processing
        case "等待确认": return .waiting
        case "成功": return .success
        case "错误": return .error
        case "未知": return .unknown
        case "未连接": return .disconnected
        default: return nil
        }
    }
}
