import Foundation
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "CodexSetupManager")

/// Codex Hooks 配置状态。
enum CodexSetupStatus: Equatable {
    case unknown
    case notConfigured(reason: String)
    case partial(missingHooks: [String], scriptPath: String?)
    case configured(scriptPath: String)

    var isConfigured: Bool {
        if case .configured = self { return true }
        return false
    }
}

enum CodexSetupError: LocalizedError {
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

/// 负责 Codex Hooks 的自动安装与静态检测。
/// Codex 是 CLI 工具，配置写入 `~/.codex/hooks.json`（三层嵌套结构，与 Claude Code 一致）。
@MainActor
final class CodexSetupManager: ObservableObject {
    static let shared = CodexSetupManager()

    @Published private(set) var status: CodexSetupStatus = .unknown
    @Published private(set) var isInstalling = false
    @Published private(set) var lastInstallError: String?

    private let fileManager = FileManager.default

    /// 本机是否已安装 Codex（CLI 或 ChatGPT 桌面版）。由 `refresh()` 同步检测并更新，UI 可观察。
    @Published private(set) var isCodexInstalled: Bool = false

    /// 检测 Codex 是否已安装：`codex` CLI 二进制，或 ChatGPT.app（Codex 桌面版，内置 Codex 引擎）。
    private func detectCodexInstalled() -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.codex/bin/codex"
        ]
        // 补充 nvm 用户：~/.nvm/versions/node/*/bin/codex（遍历所有已装 node 版本）。
        let nvmVersionsDir = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmVersionsDir.path) {
            candidates.append(contentsOf: versions.map { "\(nvmVersionsDir.path)/\($0)/bin/codex" })
        }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return true
        }

        // ChatGPT.app（Codex 桌面版）
        let chatGPTApps = [
            "/Applications/ChatGPT.app",
            "\(home)/Applications/ChatGPT.app"
        ]
        for path in chatGPTApps where fileManager.fileExists(atPath: path) {
            return true
        }
        return false
    }

    nonisolated let requiredHooks: [String] = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "SubagentStart",
        "SubagentStop",
        "Stop"
    ]

    nonisolated private var hooksJSONURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
    }

    nonisolated private var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks/codex-bridge.sh")
    }

    private init() {}

    /// 刷新安装状态与静态配置检测结果。
    func refresh() {
        isCodexInstalled = detectCodexInstalled()
        Task {
            let newStatus = await performStaticCheck()
            self.status = newStatus
        }
    }

    /// 自动安装：将应用内桥接脚本复制到 ~/.codex/hooks/ 并合并写入 hooks.json。
    func installAutomatically() {
        guard !isInstalling else { return }
        guard isCodexInstalled else { return }
        isInstalling = true
        lastInstallError = nil

        Task {
            do {
                try await performInstall()
                GlowSettings.shared.setIDEEnabled(.codex, enabled: true)
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

    private func performStaticCheck() async -> CodexSetupStatus {
        // 若 agent 未安装，即使残留有配置文件，也不应视为「已配置」。
        guard isCodexInstalled else {
            return .notConfigured(reason: I18n.shared.string(.onboardingCodexNotInstalledTitle))
        }
        let fileManager = FileManager.default
        let hooksURL = hooksJSONURL
        guard fileManager.fileExists(atPath: hooksURL.path) else {
            return .notConfigured(reason: I18n.shared.string(.codexSetupMissingHooksJson))
        }

        guard let data = fileManager.contents(atPath: hooksURL.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return .notConfigured(reason: I18n.shared.string(.codexSetupInvalidHooksJson))
        }

        var scriptPath: String?
        var missingHooks: [String] = []

        for event in requiredHooks {
            guard let groups = hooks[event] as? [[String: Any]] else {
                missingHooks.append(event)
                continue
            }

            var found = false
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                for handler in handlers {
                    if let cmd = handler["command"] as? String, !cmd.isEmpty {
                        if scriptPath == nil {
                            scriptPath = resolveScriptPath(cmd)
                        }
                        found = true
                        break
                    }
                }
                if found { break }
            }
            if !found {
                missingHooks.append(event)
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
                .appendingPathComponent(".codex/\(String(cmd.dropFirst(2)))")
                .path
        }
        return (cmd as NSString).standardizingPath
    }

    // MARK: - Install

    private func performInstall() async throws {
        let fileManager = FileManager.default
        logger.info("Starting Codex Hooks auto-install...")

        let candidates: [(String, String?)] = [
            ("codex-bridge", "Resources/hooks"),
            ("codex-bridge", "hooks"),
            ("codex-bridge", nil),
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
            logger.error("codex-bridge.sh not found in bundle")
            throw CodexSetupError.bridgeScriptNotFoundInBundle
        }

        let hooksDir = defaultScriptURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: defaultScriptURL.path) {
            try fileManager.removeItem(at: defaultScriptURL)
        }
        try fileManager.copyItem(at: sourceURL, to: defaultScriptURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: defaultScriptURL.path)

        // H2 教训：读取现有 hooks.json 并合并，只改 hooks 字段，保留其他字段。
        var existingConfig: [String: Any] = [:]
        if let existingData = fileManager.contents(atPath: hooksJSONURL.path),
           let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            existingConfig = json
        }

        var hooks = existingConfig["hooks"] as? [String: Any] ?? [:]
        let scriptPath = defaultScriptURL.path

        for event in requiredHooks {
            let handler: [String: Any] = ["type": "command", "command": scriptPath]
            let groups = hooks[event] as? [[String: Any]] ?? []

            var keptGroups: [[String: Any]] = []
            for group in groups {
                guard var handlers = group["hooks"] as? [[String: Any]] else {
                    keptGroups.append(group)
                    continue
                }
                handlers.removeAll { handler in
                    guard let cmd = handler["command"] as? String else { return false }
                    return (cmd as NSString).standardizingPath == (scriptPath as NSString).standardizingPath
                }
                if handlers.isEmpty { continue }
                var g = group
                g["hooks"] = handlers
                keptGroups.append(g)
            }

            keptGroups.append(["matcher": "*", "hooks": [handler]])
            hooks[event] = keptGroups
        }

        existingConfig["hooks"] = hooks
        let configData = try JSONSerialization.data(withJSONObject: existingConfig, options: [.prettyPrinted, .sortedKeys])
        try configData.write(to: hooksJSONURL, options: .atomic)

        logger.info("Codex Hooks auto-install completed")
    }
}
