import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "FileHookAdapter")

/// 监听 IDE 通过桥接脚本写入的 JSONL 事件文件。
/// 通用文件监听，不特定于某个 IDE；Cursor 与 Claude Code 各持有一个实例。
final class FileHookAdapter: ObservableObject, IDEAdapter {
    let id: IDE

    /// 增量事件流：每解析出一条新事件即发布一次，由 StateEngine 逐条订阅处理。
    /// 取代此前的 `events` 数组，同时解决批量丢事件（H1）与无界增长（M1）。
    let eventSubject = PassthroughSubject<HookEvent, Never>()

    @Published private(set) var lastError: Error?
    @Published private(set) var isConnected: Bool = false

    private let eventsURL: URL
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var cancellables = Set<AnyCancellable>()
    private var healthCheckTimer: Timer?
    private(set) var isRunning = false
    private var lastReadOffset: UInt64 = 0

    /// 串行队列：所有 FileHandle 读取与 lastReadOffset 访问都收敛到此，
    /// 避免 DispatchSource handler 与健康检查并发读同一 FileHandle（M2 竞态）。
    private let readQueue: DispatchQueue

    /// 启动时忽略多久以前的事件，避免把历史状态当作当前状态。
    var staleEventThreshold: TimeInterval = 30

    /// 文件健康检查间隔。
    var healthCheckInterval: TimeInterval = 30

    init(id: IDE, eventsURL: URL) {
        self.id = id
        self.eventsURL = eventsURL
        self.readQueue = DispatchQueue(label: "com.liang.read-\(id.rawValue)", qos: .utility)
    }

    deinit {
        stop()
    }

    /// 启动监听。如果文件不存在会先创建空文件（仅作为监听目标，不代表事件来源）。
    func start() {
        guard !isRunning else { return }
        isRunning = true
        logger.info("FileHookAdapter.start() id=\(self.id.rawValue)")

        lastReadOffset = 0

        let directory = eventsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forReadingFrom: eventsURL) else {
            lastError = AdapterError.openFailed(path: eventsURL.path)
            logger.error("Cannot open events file: \(self.eventsURL.path)")
            isRunning = false
            return
        }

        // 启动时只接受最近的事件，避免把旧事件当作当前状态。
        readAvailableLines(from: handle, filterStale: true)
        updateLastOffset(from: handle)

        // 移动到文件末尾，只监听新增内容。
        _ = try? handle.seekToEnd()
        updateLastOffset(from: handle)

        let fd = handle.fileDescriptor
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .extend,
            queue: readQueue
        )

        newSource.setEventHandler { [weak self] in
            guard let self = self, let handle = self.fileHandle else { return }
            self.readAvailableLines(from: handle, filterStale: false)
            self.updateLastOffset(from: handle)
        }

        newSource.setCancelHandler {
            try? handle.close()
        }

        newSource.resume()

        self.fileHandle = handle
        self.source = newSource
        self.isConnected = true

        startHealthCheck()
    }

    func stop() {
        guard isRunning else { return }
        logger.info("FileHookAdapter.stop() id=\(self.id.rawValue)")
        isRunning = false
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        source?.cancel()
        source = nil
        fileHandle = nil
        isConnected = false
    }

    /// 强制重连：用于文件被清空/轮转或读取异常时。
    func restart() {
        logger.info("FileHookAdapter.restart() id=\(self.id.rawValue)")
        stop()
        start()
    }

    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    private func performHealthCheck() {
        guard isRunning else { return }

        let fileExists = FileManager.default.fileExists(atPath: eventsURL.path)
        if !fileExists {
            logger.error("Events file missing, triggering reconnect")
            restart()
            return
        }

        // 文件大小与偏移的比较、以及可能的追读，全部收敛到 readQueue，
        // 避免与 DispatchSource handler 并发读同一 FileHandle（M2 竞态）。
        readQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            let currentSize = (try? FileManager.default.attributesOfItem(atPath: self.eventsURL.path)[.size] as? UInt64) ?? 0

            if currentSize < self.lastReadOffset {
                logger.error("Events file truncated (currentSize=\(currentSize), lastOffset=\(self.lastReadOffset)), triggering reconnect")
                DispatchQueue.main.async { self.restart() }
                return
            }

            // 如果文件增长但 DispatchSource 没有触发（极端情况），主动追读。
            if currentSize > self.lastReadOffset, let handle = self.fileHandle {
                self.readAvailableLines(from: handle, filterStale: false)
                self.updateLastOffset(from: handle)
            }
        }
    }

    private func updateLastOffset(from handle: FileHandle) {
        lastReadOffset = handle.offsetInFile
    }

    private func readAvailableLines(from handle: FileHandle, filterStale: Bool) {
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        guard let text = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = AdapterError.decodeFailed
            }
            logger.error("Failed to decode events file")
            return
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var newEvents: [HookEvent] = lines.compactMap { line in
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return nil
            }
            return HookEvent(payload: json)
        }

        if filterStale {
            let cutoff = Date().addingTimeInterval(-staleEventThreshold)
            newEvents = newEvents.filter { $0.timestamp >= cutoff }
            if newEvents.count < lines.count {
                logger.info("Filtered \(lines.count - newEvents.count) stale events at startup")
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for event in newEvents {
                self.eventSubject.send(event)
            }
            self.isConnected = true
            if !newEvents.isEmpty {
                logger.info("Received \(newEvents.count) new events")
            }
        }
    }
}

enum AdapterError: LocalizedError {
    case openFailed(path: String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .openFailed(let path):
            return I18n.shared.string(.cannotOpenEventsFile, path)
        case .decodeFailed:
            return I18n.shared.string(.eventsFileDecodeFailed)
        }
    }
}

extension FileHookAdapter {
    /// 各已接入 IDE 的事件文件路径。
    static func defaultEventsURL(for id: IDE) -> URL {
        let filename: String
        switch id {
        case .cursor: filename = "cursor-events.jsonl"
        case .claudeCode: filename = "claude-events.jsonl"
        default: filename = "\(id.rawValue.lowercased())-events.jsonl"
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".liang")
            .appendingPathComponent(filename)
    }

    static let cursor = FileHookAdapter(id: .cursor, eventsURL: defaultEventsURL(for: .cursor))
    static let claudeCode = FileHookAdapter(id: .claudeCode, eventsURL: defaultEventsURL(for: .claudeCode))

    /// 所有已接入的 adapter（新增 IDE 时在此登记）。
    static let all: [FileHookAdapter] = [cursor, claudeCode]
}
