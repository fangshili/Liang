import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "StateEngine")

/// 状态引擎：把原始 Hook 事件合并为稳定状态。
/// T5 责任：去重、超时恢复、Cursor 退出/未连接检测、最近事件记录。
/// 不直接操作 UI 或光晕（T6）。
final class StateEngine: ObservableObject {
    static let shared = StateEngine()

    @Published private(set) var state: LiangState = .idle
    @Published private(set) var lastEvent: HookEvent?
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var recentTasks: [TaskItem] = []

    private let adapters: [FileHookAdapter]
    private var cancellables = Set<AnyCancellable>()
    private var timeoutTimer: Timer?
    private var successResetTimer: Timer?
    private var heartbeatTimer: Timer?
    private var isStarted = false

    /// 内存中保留的最近任务上限（不持久化）。
    static let maxRecentTasks = 50
    /// 列表 UI 默认展示数量。
    static let defaultVisibleTasks = 10

    /// processing 状态超时恢复为 idle 的时间。
    var processingTimeout: TimeInterval
    /// waiting 状态是否启用超时（默认关闭，等待用户主动输入）。
    var waitingTimeoutEnabled: Bool
    /// 成功状态最多保持时间。
    var successMaxDuration: TimeInterval
    /// 最近事件去重窗口。
    var deduplicationWindow: TimeInterval
    /// 长时间无 Cursor 事件后自动回到 idle（默认 5 分钟）。
    var sessionIdleTimeout: TimeInterval = 300

    private var recentSignatures: [String: Date] = [:]
    private var settings: GlowSettings { GlowController.shared.settings }

    init(adapters: [FileHookAdapter] = FileHookAdapter.all) {
        self.adapters = adapters
        let defaults = GlowSettings(defaults: true)
        self.processingTimeout = defaults.processingTimeout
        self.successMaxDuration = defaults.successMaxDuration
        self.waitingTimeoutEnabled = defaults.waitingTimeoutEnabled
        self.deduplicationWindow = defaults.deduplicationWindow
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        logger.info("StateEngine.start()")

        bindSettings()

        // 订阅所有 adapter 的事件与连接状态（共用状态机）。
        for adapter in adapters {
            adapter.eventSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    self?.handle(event: event)
                }
                .store(in: &cancellables)

            adapter.$isConnected
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshConnectivity()
                }
                .store(in: &cancellables)
        }

        // 初始按各 IDE 的启用状态启停 adapter。
        applyAdapterStates()

        // 监听各 IDE 的启用开关变化。
        GlowController.shared.settings.$cursorHooksEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyAdapterStates()
            }
            .store(in: &cancellables)

        GlowController.shared.settings.$ideEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyAdapterStates()
            }
            .store(in: &cancellables)
    }

    func stop() {
        guard isStarted else { return }
        logger.info("StateEngine.stop()")
        isStarted = false
        adapters.forEach { $0.stop() }
        cancellables.removeAll()
        invalidateTimers()
    }

    /// 睡眠前暂停所有 adapter，避免持有过期的文件描述符。
    func pauseAllAdapters() {
        adapters.forEach { $0.stop() }
    }

    /// 唤醒后恢复所有已启用的 adapter。
    func resumeAllAdapters() {
        for adapter in adapters where settings.isIDEEnabled(adapter.id) {
            adapter.restart()
        }
        refreshConnectivity()
    }

    /// 按各 IDE 的启用状态启停对应 adapter，并维护心跳与连接状态。
    /// M7 修复：启动/运行时若 hooks 关闭，不启动对应 adapter；全部关闭时进入 disconnected。
    private func applyAdapterStates() {
        var anyRunning = false
        for adapter in adapters {
            if settings.isIDEEnabled(adapter.id) {
                adapter.start()
                anyRunning = true
            } else {
                adapter.stop()
            }
        }

        if anyRunning {
            startHeartbeat()
        } else {
            invalidateTimers()
            transition(to: .disconnected)
        }
    }

    /// 所有 adapter 都未连接且尚无事件时，回到 disconnected。
    private func refreshConnectivity() {
        let anyConnected = adapters.contains { $0.isConnected }
        if !anyConnected && lastEvent == nil {
            state = .disconnected
        }
    }

    private func bindSettings() {
        settings.$processingTimeout
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.processingTimeout = value }
            .store(in: &cancellables)

        settings.$successMaxDuration
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.successMaxDuration = value }
            .store(in: &cancellables)

        settings.$waitingTimeoutEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.waitingTimeoutEnabled = value }
            .store(in: &cancellables)

        settings.$deduplicationWindow
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.deduplicationWindow = value }
            .store(in: &cancellables)
    }

    /// 手动清除错误状态（用户通过菜单栏操作）。
    func clearError() {
        guard state == .error else { return }
        transition(to: .idle)
    }

    private func handle(event: HookEvent) {
        guard !isDuplicate(event) else { return }

        lastEvent = event
        lastEventAt = event.timestamp
        resetHeartbeat()

        let newState = event.liangState
        updateRecentTasks(with: event)

        // 优先级规则：
        // 1. error 保持到手动清除，或被 idle/sessionEnd/success 明确结束；
        //    不允许 processing 覆盖 error。
        // 2. waiting 保持到用户发送新消息（beforeSubmitPrompt）或 sessionEnd/idle；
        //    默认不超时，等待用户主动输入。
        // 3. success 保持最多 3 分钟，或被新事件打断。
        if state == .error && newState == .processing {
            // 保持 error，不处理新 processing。
            return
        }

        transition(to: newState, conversationID: event.conversationID)
    }

    private func transition(to newState: LiangState, conversationID: String? = nil) {
        logger.info("state transition: \(String(describing: self.state)) -> \(String(describing: newState))")
        let previousState = state
        state = newState

        // 兜底：当全局状态从 processing/waiting/success 离开（任务结束/超时）时，
        // 同步更新对应任务状态，避免 stop 事件 conversationID 缺失或同时存在多个任务时列表卡在处理中。
        let shouldPropagate = previousState == .processing || previousState == .waiting || previousState == .success
        if shouldPropagate {
            switch newState {
            case .success, .error, .idle:
                let now = Date()
                for index in recentTasks.indices {
                    let task = recentTasks[index]
                    guard task.state == previousState else { continue }
                    // 并行会话隔离：事件携带会话 ID 时，仅更新同会话任务，
                    // 避免把仍在运行的其他会话任务误标为终态（M3）。
                    if let conversationID, !conversationID.isEmpty {
                        guard task.conversationID == conversationID else { continue }
                    }
                    recentTasks[index].state = newState
                    recentTasks[index].updatedAt = now
                    // 如果原任务标题来自 tool/progress hook，全局收尾时同步为终态标题。
                    if !terminalHooks.contains(task.sourceHook) {
                        recentTasks[index].title = fallbackTitle(for: newState, id: task.id)
                    }
                }
            default:
                break
            }
        }

        invalidateTimers()

        switch newState {
        case .processing:
            startProcessingTimeoutTimer()
        case .waiting:
            // waiting 默认不超时，除非显式开启。
            if waitingTimeoutEnabled {
                startWaitingTimeoutTimer()
            }
        case .success:
            startSuccessResetTimer()
        case .error:
            // 错误状态保持，直到用户手动清除或收到结束事件。
            break
        case .idle, .unknown, .disconnected:
            break
        }
    }

    private func startProcessingTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: processingTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .processing {
                logger.info("Processing timeout, falling back to idle")
                self.transition(to: .idle)
            }
        }
    }

    private func startWaitingTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: processingTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .waiting {
                logger.info("Waiting timeout, falling back to idle")
                self.transition(to: .idle)
            }
        }
    }

    private func startSuccessResetTimer() {
        successResetTimer = Timer.scheduledTimer(withTimeInterval: successMaxDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .success {
                logger.info("Success duration exceeded, falling back to idle")
                self.transition(to: .idle)
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: sessionIdleTimeout, repeats: true) { [weak self] _ in
            self?.checkSessionIdle()
            self?.cleanupStaleTasks()
        }
    }

    private func resetHeartbeat() {
        // 每次收到事件重置心跳计时器，避免在活跃时误触发。
        startHeartbeat()
    }

    private func checkSessionIdle() {
        guard let lastEventAt = lastEventAt else { return }
        let idle = Date().timeIntervalSince(lastEventAt)
        guard idle >= sessionIdleTimeout else { return }

        // 长时间无事件，认为 Cursor 会话已结束或 App 已退出，回到 idle。
        // 错误状态保留，不自动清除。
        switch state {
        case .processing, .waiting, .success:
            logger.info("Session idle for \(Int(idle))s, falling back to idle")
            transition(to: .idle)
        case .error, .idle, .unknown, .disconnected:
            break
        }
    }

    /// 清理长时间卡住的 processing/waiting 任务，避免 ID 对不齐导致列表里永远有“进行中”任务。
    private func cleanupStaleTasks() {
        guard state != .processing else { return }
        let now = Date()
        let timeout = processingTimeout
        for index in recentTasks.indices where recentTasks[index].state == .processing || recentTasks[index].state == .waiting {
            let task = recentTasks[index]
            if now.timeIntervalSince(task.updatedAt) > timeout {
                logger.info("Cleaning up stale task \(task.title) after \(Int(timeout))s")
                recentTasks[index].state = .idle
                recentTasks[index].updatedAt = now
            }
        }
    }

    private func invalidateTimers() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        successResetTimer?.invalidate()
        successResetTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func isDuplicate(_ event: HookEvent) -> Bool {
        let signature = "\(event.hook)|\(event.conversationID ?? "")|\(event.generationID ?? "")|\(event.taskID ?? "")|\(event.status ?? "")"
        let now = Date()

        // 清理过期签名。
        recentSignatures = recentSignatures.filter { now.timeIntervalSince($0.value) < deduplicationWindow }

        if recentSignatures[signature] != nil {
            return true
        }
        recentSignatures[signature] = now
        return false
    }

    /// 这些 hook 通常只携带会话元数据，不描述具体任务，更新时应保留已有更具体的标题。
    /// 终态 hook（sessionEnd / stop / subagentStop）不在此列，以便让标题跟随结束事件。
    private let genericTitleHooks: Set<String> = [
        "sessionStart", "beforeSubmitPrompt", "afterAgentResponse",
        "afterAgentThought", "postToolUseFailure", "subagentStart"
    ]

    /// 被认为是终态标题来源的 hook。
    private let terminalHooks: Set<String> = ["sessionEnd", "stop", "subagentStop"]

    private func shouldKeepExistingTitle(for event: HookEvent) -> Bool {
        genericTitleHooks.contains(event.hook)
    }

    /// 当全局状态收尾且原任务没有终态标题时，生成一个与状态对应的兜底标题。
    private func fallbackTitle(for state: LiangState, id: String) -> String {
        let base: String
        switch state {
        case .success, .error:
            base = I18n.shared.string(.taskTaskEnd)
        default:
            base = I18n.shared.string(.taskSessionEnd)
        }
        let shortID = String(id.prefix(8))
        return "\(base) #\(shortID)"
    }

    /// 用新事件更新内存任务列表：按 conversationID 去重，保留最新状态与标题。
    /// sessionEnd 如果没有命中已有任务，则不单独创建新记录，避免“Start Session + End Session”同时出现。
    private func updateRecentTasks(with event: HookEvent) {
        // subagent 是主对话的一部分，不单独成卡片（合并进主任务），
        // 避免 subagent 事件覆盖主任务的标题与状态。
        if event.hook == "subagentStart" || event.hook == "subagentStop" {
            return
        }

        let primaryKey = event.conversationID ?? event.id.uuidString
        var task = TaskItem(event: event)
        let matchedIndex = indexOfTask(matching: event, primaryKey: primaryKey)

        if let index = matchedIndex {
            let existing = recentTasks[index]
            // 如果新事件是通用元数据 hook（不带具体 tool/subagent 信息），保留已有标题和 sourceHook。
            if shouldKeepExistingTitle(for: event) {
                task.title = existing.title
                task.sourceHook = existing.sourceHook
            }
            // 只要新事件时间不早于现有记录，就更新为该任务最新状态。
            guard event.timestamp >= existing.updatedAt else { return }
            recentTasks.remove(at: index)
        } else if event.hook == "sessionEnd" {
            // sessionEnd 未命中任何任务时不创建新任务卡片，它只用来触发全局状态回到 idle。
            return
        }

        recentTasks.insert(task, at: 0)
        if recentTasks.count > Self.maxRecentTasks {
            recentTasks.removeLast(recentTasks.count - Self.maxRecentTasks)
        }
    }

    /// 按 conversationID / taskID / generationID 匹配已有任务。
    /// 部分 Cursor Hook 事件（如 stop）可能缺少 conversation_id，用其他 ID 兜底。
    private func indexOfTask(matching event: HookEvent, primaryKey: String) -> Int? {
        if let index = recentTasks.firstIndex(where: { $0.conversationID == primaryKey && !primaryKey.isEmpty }) {
            return index
        }
        if let taskID = event.taskID, !taskID.isEmpty,
           let index = recentTasks.firstIndex(where: { $0.conversationID == taskID || $0.id == taskID }) {
            return index
        }
        if let generationID = event.generationID, !generationID.isEmpty,
           let index = recentTasks.firstIndex(where: { $0.conversationID == generationID || $0.id == generationID }) {
            return index
        }
        return nil
    }

    /// 供 UI 使用的排序后任务列表：processing/waiting 在前，其次 error/success/idle/unknown。
    var orderedTasks: [TaskItem] {
        recentTasks.sorted {
            if $0.state.priority != $1.state.priority {
                return $0.state.priority > $1.state.priority
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
