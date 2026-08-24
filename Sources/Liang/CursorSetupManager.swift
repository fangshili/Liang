import Foundation
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "CursorSetupManager")

/// Cursor Hooks 配置状态。
enum CursorSetupStatus: Equatable {
    case unknown
    case notConfigured(reason: String)
    case partial(missingHooks: [String], scriptPath: String?)
    case configured(scriptPath: String)

    var isConfigured: Bool {
        if case .configured = self { return true }
        return false
    }
}

enum CursorSetupError: LocalizedError {
    case bridgeScriptNotFoundInBundle
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .bridgeScriptNotFoundInBundle:
            return I18n.shared.string(.cursorSetupResourceMissing)
        case .writeFailed(let error):
            return I18n.shared.string(.cursorSetupWriteFailed, error.localizedDescription)
        }
    }
}

/// 负责 Cursor Hooks 的自动安装与静态检测。
@MainActor
final class CursorSetupManager: ObservableObject {
    static let shared = CursorSetupManager()

    @Published private(set) var status: CursorSetupStatus = .unknown
    @Published private(set) var isInstalling = false
    @Published private(set) var lastInstallError: String?

    private let fileManager = FileManager.default

    /// 本机是否已安装 Cursor 应用。由 `refresh()` 同步检测并更新，UI 可观察。
    @Published private(set) var isCursorInstalled: Bool = false

    /// 检测 Cursor 应用是否已安装。优先检查常见安装路径，再尝试通过 bundle ID 定位。
    private func detectCursorInstalled() -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/Cursor.app",
            "\(home)/Applications/Cursor.app"
        ]
        for path in candidates where fileManager.fileExists(atPath: path) {
            return true
        }
        if #available(macOS 11.0, *) {
            let bundleIDs = ["com.todesktop.com", "com.cursor.Cursor"]
            for bundleID in bundleIDs {
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                    return true
                }
            }
        }
        return false
    }

    nonisolated let requiredHooks: [String] = [
        "sessionStart",
        "sessionEnd",
        "beforeSubmitPrompt",
        "preToolUse",
        "postToolUse",
        "postToolUseFailure",
        "beforeShellExecution",
        "afterShellExecution",
        "beforeMCPExecution",
        "afterMCPExecution",
        "subagentStart",
        "subagentStop",
        "afterAgentThought",
        "afterAgentResponse",
        "stop"
    ]

    nonisolated private var hooksJSONURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
    }

    nonisolated private var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks/liang-bridge.sh")
    }

    private init() {}

    /// 刷新安装状态与静态配置检测结果。
    func refresh() {
        isCursorInstalled = detectCursorInstalled()
        Task {
            let newStatus = await performStaticCheck()
            self.status = newStatus
        }
    }

    /// 自动安装：将应用内桥接脚本复制到 ~/.cursor/hooks/ 并写入 hooks.json。
    /// 调用前应在 UI 中向用户说明将要修改的文件。
    func installAutomatically() {
        guard !isInstalling else { return }
        guard isCursorInstalled else { return }
        isInstalling = true
        lastInstallError = nil

        Task {
            do {
                try await performInstall()
                let newStatus = await performStaticCheck()
                self.status = newStatus
                self.isInstalling = false
            } catch {
                self.lastInstallError = error.localizedDescription
                self.isInstalling = false
            }
        }
    }

    // MARK: - Static Check

    private func performStaticCheck() async -> CursorSetupStatus {
        // 若 agent 未安装，即使残留有配置文件，也不应视为「已配置」。
        guard isCursorInstalled else {
            return .notConfigured(reason: I18n.shared.string(.onboardingCursorNotInstalledTitle))
        }
        let fileManager = FileManager.default
        let hooksURL = hooksJSONURL
        guard fileManager.fileExists(atPath: hooksURL.path) else {
            return .notConfigured(reason: I18n.shared.string(.cursorSetupMissingHooksJson))
        }

        // 放宽校验：不强制 version == 1，允许 hooks.json 包含额外字段，
        // 只要存在 hooks 字典且每个必要事件都有非空 command 即可。
        guard let data = fileManager.contents(atPath: hooksURL.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: [[String: Any]]] else {
            return .notConfigured(reason: I18n.shared.string(.cursorSetupInvalidHooksJson))
        }

        var scriptPath: String?
        var missingHooks: [String] = []

        for event in requiredHooks {
            guard let commands = hooks[event],
                  let first = commands.first,
                  let cmd = first["command"] as? String, !cmd.isEmpty else {
                missingHooks.append(event)
                continue
            }
            if scriptPath == nil {
                scriptPath = resolveScriptPath(cmd)
            }
        }

        if !missingHooks.isEmpty {
            return .partial(missingHooks: missingHooks, scriptPath: scriptPath)
        }

        guard let path = scriptPath else {
            return .notConfigured(reason: I18n.shared.string(.cursorSetupMissingBridgePath))
        }
        guard fileManager.fileExists(atPath: path) else {
            return .notConfigured(reason: I18n.shared.string(.cursorSetupScriptMissing, path))
        }
        guard fileManager.isExecutableFile(atPath: path) else {
            return .notConfigured(reason: I18n.shared.string(.cursorSetupScriptNotExecutable))
        }

        return .configured(scriptPath: path)
    }

    nonisolated private func resolveScriptPath(_ command: String) -> String {
        let fileManager = FileManager.default
        var cmd = command.trimmingCharacters(in: .whitespaces)
        if cmd.hasPrefix("~/") {
            cmd = fileManager.homeDirectoryForCurrentUser.path + String(cmd.dropFirst(2))
        } else if cmd.hasPrefix("./") {
            cmd = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".cursor/\(String(cmd.dropFirst(2)))")
                .path
        }
        return (cmd as NSString).standardizingPath
    }

    // MARK: - Install

    private func performInstall() async throws {
        let fileManager = FileManager.default
        logger.info("Starting Cursor Hooks auto-install...")

        // 尝试多个可能的资源路径（SPM 资源 bundle vs .app bundle）。
        let candidates: [(String, String?)] = [
            ("liang-bridge", "Resources/hooks"),   // SPM Bundle.module
            ("liang-bridge", "hooks"),              // .app Bundle.main (manual copy)
            ("liang-bridge", nil),                  // fallback: root
        ]
        var sourceURL: URL?
        for (name, subdir) in candidates {
            if let url = Bundle.module.url(forResource: name, withExtension: "sh", subdirectory: subdir)
                ?? Bundle.main.url(forResource: name, withExtension: "sh", subdirectory: subdir) {
                sourceURL = url
                break
            }
        }
        guard let sourceURL else {
            logger.error("Bridge script not found in bundle (tried all paths)")
            throw CursorSetupError.bridgeScriptNotFoundInBundle
        }
        logger.info("Bridge script source: \(sourceURL.path)")

        let cursorDir = hooksJSONURL.deletingLastPathComponent()
        logger.info("Ensuring cursor dir: \(cursorDir.path)")
        try fileManager.createDirectory(at: cursorDir, withIntermediateDirectories: true, attributes: nil)

        let hooksDir = defaultScriptURL.deletingLastPathComponent()
        logger.info("Ensuring hooks dir: \(hooksDir.path)")
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: defaultScriptURL.path) {
            logger.info("Removing existing bridge script")
            try fileManager.removeItem(at: defaultScriptURL)
        }
        logger.info("Copying bridge script to \(self.defaultScriptURL.path)")
        try fileManager.copyItem(at: sourceURL, to: defaultScriptURL)

        logger.info("Setting executable permissions")
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: defaultScriptURL.path)

        // H2 修复：读取现有 hooks.json 并按事件名合并，仅插入/更新 Liang 条目，
        // 保留用户已有配置，避免整体覆盖破坏其他工具的 hooks。
        var existingConfig: [String: Any] = [:]
        var existingHooks: [String: [[String: Any]]] = [:]
        if let existingData = FileManager.default.contents(atPath: hooksJSONURL.path),
           let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            existingConfig = json
            if let hooks = json["hooks"] as? [String: [[String: Any]]] {
                existingHooks = hooks
            }
        }

        let liangCommand = defaultScriptURL.path
        var mergedHooks = existingHooks
        for event in requiredHooks {
            let liangEntry: [String: Any] = ["command": liangCommand]
            var commands = mergedHooks[event] ?? []
            // 移除旧的 Liang 条目（按 command 指向 liang-bridge.sh 判断），避免重复。
            commands.removeAll { entry in
                guard let cmd = entry["command"] as? String else { return false }
                return (cmd as NSString).standardizingPath == (liangCommand as NSString).standardizingPath
            }
            commands.append(liangEntry)
            mergedHooks[event] = commands
        }

        existingConfig["hooks"] = mergedHooks
        if existingConfig["version"] == nil {
            existingConfig["version"] = 1
        }
        let configData = try JSONSerialization.data(withJSONObject: existingConfig, options: [.prettyPrinted, .sortedKeys])

        // 使用原子写入，避免先删除再写入导致中途崩溃/终止时 hooks.json 丢失。
        logger.info("Writing merged hooks.json to \(self.hooksJSONURL.path)")
        try configData.write(to: hooksJSONURL, options: .atomic)

        logger.info("Cursor Hooks auto-install completed")
    }
}
