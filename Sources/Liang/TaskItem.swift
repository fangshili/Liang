import Foundation

/// 任务列表中的一行记录，按 conversationID 去重。
/// 只保留内存，不持久化。
struct TaskItem: Identifiable, Equatable {
    let id: String
    let conversationID: String
    var title: String
    var state: LiangState
    var updatedAt: Date
    let source: String
    /// 最后一次更新该任务的事件 hook，用于判断标题是否已经是终态描述。
    var sourceHook: String

    /// 从 HookEvent 创建或更新任务项。
    init(event: HookEvent) {
        self.id = event.conversationID ?? event.id.uuidString
        self.conversationID = event.conversationID ?? event.id.uuidString
        self.title = Self.title(for: event)
        self.state = event.liangState
        self.updatedAt = event.timestamp
        self.source = event.source
        self.sourceHook = event.hook
    }

    /// 根据事件内容推导可读标题，并附加任务 ID 以便区分不同会话。
    private static func title(for event: HookEvent) -> String {
        let base: String
        // 优先使用 tool 名。
        if let toolName = event.toolName, !toolName.isEmpty {
            base = localizedToolName(toolName)
        }
        // 其次使用 subagent 标识。
        else if let subagentID = event.subagentID, !subagentID.isEmpty {
            base = "\(I18n.shared.string(.taskSubtask)) \(subagentID.prefix(8))"
        }
        // 兜底：根据 hook 类型给出一个具体动词。
        else {
            switch event.hook {
            case "beforeSubmitPrompt":
                base = I18n.shared.string(.taskSubmitPrompt)
            case "sessionStart":
                base = I18n.shared.string(.taskSessionStart)
            case "sessionEnd":
                base = I18n.shared.string(.taskSessionEnd)
            case "afterAgentResponse":
                base = I18n.shared.string(.taskWaitingInput)
            case "afterAgentThought":
                base = I18n.shared.string(.taskThinking)
            case "subagentStart", "subagentStop":
                base = I18n.shared.string(.taskSubtask)
            case "stop":
                base = I18n.shared.string(.taskTaskEnd)
            default:
                base = event.hook
            }
        }

        let id = String(event.conversationID?.prefix(8)
            ?? event.taskID?.prefix(8)
            ?? event.id.uuidString.prefix(8))
        return "\(base) #\(id)"
    }

    private static func localizedToolName(_ name: String) -> String {
        let map: [String: LocalizedKey] = [
            "read_file": .toolReadFile,
            "write_to_file": .toolWriteFile,
            "replace_in_file": .toolEditFile,
            "search_file": .toolSearchFile,
            "search_content": .toolSearchContent,
            "execute_command": .toolExecuteCommand,
            "web_search": .toolWebSearch,
            "web_fetch": .toolWebFetch,
            "ask_followup_question": .toolAskUser,
            "mcp_call_tool": .toolCallTool
        ]
        return map[name].map { I18n.shared.string($0) } ?? name
    }
}
