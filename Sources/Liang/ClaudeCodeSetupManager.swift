import Foundation
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "ClaudeCodeSetupManager")

/// Claude Code Hooks 配置状态。
enum ClaudeCodeSetupStatus: Equatable {
    case unknown
    case notConfigured(reason: String)
    case partial(missingHooks: [String], scriptPath: String?)
    case configured(scriptPath: String)

    var isConfigured: Bool {
        if case .configured = self { return true }
        return false
    }
}

enum ClaudeCodeSetupError: LocalizedError {
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

/// 负责 Claude Code Hooks 的自动安装与静态检测。
/// Claude Code 是 CLI 工具，配置写入 `~/.claude/settings.json`（三层嵌套结构，含 matcher 与 type）。
@MainActor
final class ClaudeCodeSetupManager: ObservableObject {
    static let shared = ClaudeCodeSetupManager()

    @Published private(set) var status: ClaudeCodeSetupStatus = .unknown
    @Published private(set) var isInstalling = false
    @Published private(set) var lastInstallError: String?

    private let fileManager = FileManager.default

    /// 本机是否已安装 Claude Code CLI。由 `refresh()` 同步检测并更新，UI 可观察。
    @Published private(set) var isClaudeCodeInstalled: Bool = false

    /// 检测 Claude Code CLI 是否已安装：只认可执行的 `claude` 二进制。
    /// 注意：不能检查 `~/.claude` 目录——Claude Desktop 桌面应用也会创建该目录，
    /// 会导致误判为已安装（而 Desktop 并不执行 hooks）。
    private func detectClaudeCodeInstalled() -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude"
        ]
        // 补充 nvm 用户：~/.nvm/versions/node/*/bin/claude（遍历所有已装 node 版本）。
        let nvmVersionsDir = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmVersionsDir.path) {
            candidates.append(contentsOf: versions.map { "\(nvmVersionsDir.path)/\($0)/bin/claude" })
        }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
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
        "PostToolUseFailure",
        "SubagentStart",
        "SubagentStop",
        "Stop",
        "StopFailure"
    ]

    nonisolated private var settingsJSONURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    nonisolated private var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/claude-bridge.sh")
    }

    private init() {}

    /// 刷新安装状态与静态配置检测结果。
    func refresh() {
        isClaudeCodeInstalled = detectClaudeCodeInstalled()
        Task {
            let newStatus = await performStaticCheck()
            self.status = newStatus
        }
    }

    /// 自动安装：将应用内桥接脚本复制到 ~/.claude/hooks/ 并合并写入 settings.json。
    func installAutomatically() {
        guard !isInstalling else { return }
        guard isClaudeCodeInstalled else { return }
        isInstalling = true
        lastInstallError = nil

        Task {
            do {
                try await performInstall()
                // 配置成功即自动启用，与 Cursor 首次配置即启用（cursorHooksEnabled 默认 true）的行为保持一致。
                GlowSettings.shared.setIDEEnabled(.claudeCode, enabled: true)
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

    private func performStaticCheck() async -> ClaudeCodeSetupStatus {
        let fileManager = FileManager.default
        let settingsURL = settingsJSONURL
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .notConfigured(reason: I18n.shared.string(.claudeSetupMissingSettingsJson))
        }

        guard let data = fileManager.contents(atPath: settingsURL.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return .notConfigured(reason: I18n.shared.string(.claudeSetupInvalidSettingsJson))
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
                .appendingPathComponent(".claude/\(String(cmd.dropFirst(2)))")
                .path
        }
        return (cmd as NSString).standardizingPath
    }

    // MARK: - Install

    private func performInstall() async throws {
        let fileManager = FileManager.default
        logger.info("Starting Claude Code Hooks auto-install...")

        // 尝试多个可能的资源路径（SPM 资源 bundle vs .app bundle）。
        let candidates: [(String, String?)] = [
            ("claude-bridge", "Resources/hooks"),   // SPM Bundle.module
            ("claude-bridge", "hooks"),              // .app Bundle.main (manual copy)
            ("claude-bridge", nil),                  // fallback: root
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
            logger.error("claude-bridge.sh not found in bundle")
            throw ClaudeCodeSetupError.bridgeScriptNotFoundInBundle
        }

        let hooksDir = defaultScriptURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: defaultScriptURL.path) {
            try fileManager.removeItem(at: defaultScriptURL)
        }
        try fileManager.copyItem(at: sourceURL, to: defaultScriptURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: defaultScriptURL.path)

        // H2 教训：读取现有 settings.json 并合并，只改 hooks 字段，
        // 保留 permissions / model / env / statusLine 等用户既有配置。
        var existingConfig: [String: Any] = [:]
        if let existingData = fileManager.contents(atPath: settingsJSONURL.path),
           let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            existingConfig = json
        }

        var hooks = existingConfig["hooks"] as? [String: Any] ?? [:]
        let scriptPath = defaultScriptURL.path

        for event in requiredHooks {
            let handler: [String: Any] = ["type": "command", "command": scriptPath]
            let groups = hooks[event] as? [[String: Any]] ?? []

            // 移除旧的 Liang 条目（按 command 指向 claude-bridge.sh），保留其他 handler。
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
        try configData.write(to: settingsJSONURL, options: .atomic)

        logger.info("Claude Code Hooks auto-install completed")
    }
}
