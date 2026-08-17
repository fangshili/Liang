import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "CursorHookAdapter")

/// 监听 Cursor 通过桥接脚本写入的 JSONL 事件文件。
final class CursorHookAdapter: ObservableObject, IDEAdapter {
    var id: IDE { .cursor }
    static let defaultEventsPath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".liang")
            .appendingPathComponent("cursor-events.jsonl")
    }()

    @Published private(set) var events: [HookEvent] = []
    @Published private(set) var lastError: Error?
    @Published private(set) var isConnected: Bool = false

    private let eventsURL: URL
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var cancellables = Set<AnyCancellable>()
    private var healthCheckTimer: Timer?
    private(set) var isRunning = false
    private var lastReadOffset: UInt64 = 0

    /// 启动时忽略多久以前的事件，避免把历史状态当作当前状态。
    var staleEventThreshold: TimeInterval = 30

    /// 文件健康检查间隔。
    var healthCheckInterval: TimeInterval = 30

    init(eventsURL: URL = CursorHookAdapter.defaultEventsPath) {
        self.eventsURL = eventsURL
    }

    deinit {
        stop()
    }

    /// 启动监听。如果文件不存在会先创建空文件（仅作为监听目标，不代表事件来源）。
    func start() {
        guard !isRunning else { return }
        isRunning = true
        logger.info("CursorHookAdapter.start()")

        events = []
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
            queue: DispatchQueue.global(qos: .utility)
        )

        newSource.setEventHandler { [weak self] in
            self?.readAvailableLines(from: handle, filterStale: false)
            self?.updateLastOffset(from: handle)
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
        logger.info("CursorHookAdapter.stop()")
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
        logger.info("CursorHookAdapter.restart()")
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
        let currentSize = (try? FileManager.default.attributesOfItem(atPath: eventsURL.path)[.size] as? UInt64) ?? 0

        if !fileExists {
            logger.error("Events file missing, triggering reconnect")
            restart()
            return
        }

        if currentSize < self.lastReadOffset {
            logger.error("Events file truncated (currentSize=\(currentSize), lastOffset=\(self.lastReadOffset)), triggering reconnect")
            restart()
            return
        }

        // 如果文件增长但 DispatchSource 没有触发（极端情况），主动追读。
        if currentSize > lastReadOffset, let handle = fileHandle {
            readAvailableLines(from: handle, filterStale: false)
            updateLastOffset(from: handle)
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
            return HookEvent(cursorPayload: json)
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
            self.events.append(contentsOf: newEvents)
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

extension CursorHookAdapter {
    static let shared = CursorHookAdapter()
}
