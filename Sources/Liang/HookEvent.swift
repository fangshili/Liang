import Foundation

/// 统一事件模型：所有 IDE Adapter 都应转换为该结构。
struct HookEvent: Identifiable {
    let id: UUID
    let source: String
    let hook: String
    let timestamp: Date
    let conversationID: String?
    let generationID: String?
    let taskID: String?
    let toolName: String?
    let toolUseID: String?
    let subagentID: String?
    let status: String?
    let failureType: String?
    let durationMs: Double?
    let rawPayload: [String: Any]?

    init(
        id: UUID = UUID(),
        source: String,
        hook: String,
        timestamp: Date,
        conversationID: String? = nil,
        generationID: String? = nil,
        taskID: String? = nil,
        toolName: String? = nil,
        toolUseID: String? = nil,
        subagentID: String? = nil,
        status: String? = nil,
        failureType: String? = nil,
        durationMs: Double? = nil,
        rawPayload: [String: Any]? = nil
    ) {
        self.id = id
        self.source = source
        self.hook = hook
        self.timestamp = timestamp
        self.conversationID = conversationID
        self.generationID = generationID
        self.taskID = taskID
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.subagentID = subagentID
        self.status = status
        self.failureType = failureType
        self.durationMs = durationMs
        self.rawPayload = rawPayload
    }
}

extension HookEvent {
    /// 把 Hook 事件映射为 Liang 状态（与 StateEngine.map(event:) 逻辑一致）。
    var liangState: LiangState {
        switch hook {
        case "sessionStart",
             "beforeSubmitPrompt",
             "preToolUse",
             "subagentStart",
             "afterAgentThought",
             "postToolUse",
             "postToolUseFailure",
             "afterShellExecution",
             "afterMCPExecution":
            return .processing
        case "afterAgentResponse",
             "beforeShellExecution",
             "beforeMCPExecution":
            return .waiting
        case "subagentStop", "stop":
            let normalized = status?.lowercased() ?? ""
            if normalized == "completed" { return .success }
            if normalized == "error" || normalized == "aborted" { return .error }
            return .processing
        case "sessionEnd":
            return .idle
        default:
            return .unknown
        }
    }

    /// 从 Cursor Hook 桥接脚本输出的 JSON 字典解析。
    init?(cursorPayload: [String: Any]) {
        guard let hook = cursorPayload["hook"] as? String else { return nil }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp: Date
        if let timestampString = cursorPayload["timestamp"] as? String,
           let parsed = dateFormatter.date(from: timestampString) {
            timestamp = parsed
        } else {
            timestamp = Date()
        }

        self.init(
            source: (cursorPayload["source"] as? String) ?? "cursor",
            hook: hook,
            timestamp: timestamp,
            conversationID: cursorPayload["conversation_id"] as? String,
            generationID: cursorPayload["generation_id"] as? String,
            taskID: cursorPayload["tool_use_id"] as? String ?? cursorPayload["subagent_id"] as? String,
            toolName: cursorPayload["tool_name"] as? String,
            toolUseID: cursorPayload["tool_use_id"] as? String,
            subagentID: cursorPayload["subagent_id"] as? String,
            status: cursorPayload["status"] as? String,
            failureType: cursorPayload["failure_type"] as? String,
            durationMs: cursorPayload["duration_ms"] as? Double,
            rawPayload: cursorPayload
        )
    }
}
