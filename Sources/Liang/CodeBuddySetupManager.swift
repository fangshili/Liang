import Foundation
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.liang", category: "CodeBuddySetupManager")

/// CodeBuddy Hooks 配置状态。
enum CodeBuddySetupStatus: Equatable {
    case unknown
    case notConfigured(reason: String)
    case partial(missingHooks: [String], scriptPath: String?)
    case configured(scriptPath: String)

    var isConfigured: Bool {
        if case .configured = self { return true }
        return false
    }
}

enum CodeBuddySetupError: LocalizedError {
    case bridgeScriptNotFoundInBundle
    case writeFailed(Error)
    case configParseFailed(String)

    var errorDescription: String? {
        switch self {
        case .bridgeScriptNotFoundInBundle:
            return I18n.shared.string(.cursorSetupResourceMissing)
        case .writeFailed(let error):
            return I18n.shared.string(.cursorSetupWriteFailed, error.localizedDescription)
        case .configParseFailed(let path):
            return I18n.shared.string(.configParseFailed, path)
        }
    }
}

/// 负责 CodeBuddy Hooks 的自动安装与静态检测。
/// CodeBuddy Code 是 CLI 工具，配置写入 `~/.codebuddy/settings.json`（三层嵌套结构，含 matcher 与 type）。
@MainActor
final class CodeBuddySetupManager: ObservableObject {
    static let shared = CodeBuddySetupManager()

    @Published private(set) var status: CodeBuddySetupStatus = .unknown
    @Published private(set) var isInstalling = false
    @Published private(set) var lastInstallError: String?

    private let fileManager = FileManager.default

    /// 本机是否已安装 CodeBuddy Code CLI。由 `refresh()` 同步检测并更新，UI 可观察。
    @Published private(set) var isCodeBuddyInstalled: Bool = false

    /// 检测 CodeBuddy Code CLI 是否已安装：只认可执行的 `codebuddy` 二进制。
    /// 覆盖三种官方安装方式：npm 全局、Homebrew、官方 install.sh 原生二进制。
    private func detectCodeBuddyInstalled() -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/codebuddy",        // Homebrew (Apple Silicon)
            "/usr/local/bin/codebuddy",           // Homebrew (Intel)
            "\(home)/.npm-global/bin/codebuddy",  // npm/pnpm/yarn 全局
            "\(home)/.local/bin/codebuddy",       // 官方 install.sh / 原生二进制
            "\(home)/.codebuddy/bin/codebuddy"    // 原生二进制可能路径
        ]
        // 补充 nvm 用户：~/.nvm/versions/node/*/bin/codebuddy（遍历所有已装 node 版本）。
        let nvmVersionsDir = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmVersionsDir.path) {
            candidates.append(contentsOf: versions.map { "\(nvmVersionsDir.path)/\($0)/bin/codebuddy" })
        }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return true
        }
        return false
    }

    // CodeBuddy 事件（无 SubagentStart / PostToolUseFailure / StopFailure）。
    // PermissionRequest（权限对话框出现）/ Notification（idle_prompt）→ waiting，桥接脚本已映射。
    nonisolated let requiredHooks: [String] = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "SubagentStop",
        "Stop",
        "Notification",
        "PermissionRequest"
    ]

    nonisolated private var settingsJSONURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codebuddy/settings.json")
    }

    nonisolated private var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codebuddy/hooks/codebuddy-bridge.sh")
    }

    private init() {}

    /// 刷新安装状态与静态配置检测结果。
    func refresh() {
        isCodeBuddyInstalled = detectCodeBuddyInstalled()
        Task {
            let newStatus = await performStaticCheck()
            self.status = newStatus
        }
    }

    /// 自动安装：将应用内桥接脚本复制到 ~/.codebuddy/hooks/ 并合并写入 settings.json。
    func installAutomatically() {
        guard !isInstalling else { return }
        guard isCodeBuddyInstalled else { return }
        isInstalling = true
        lastInstallError = nil

        Task {
            do {
                try await performInstall()
                // 配置成功即自动启用，与 Claude Code 首次配置即启用的行为保持一致。
                GlowSettings.shared.setIDEEnabled(.codeBuddy, enabled: true)
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

    private func performStaticCheck() async -> CodeBuddySetupStatus {
        // 若 agent 未安装，即使残留有配置文件，也不应视为「已配置」。
        guard isCodeBuddyInstalled else {
            return .notConfigured(reason: I18n.shared.string(.onboardingCodebuddyNotInstalledTitle))
        }
        let fileManager = FileManager.default
        let settingsURL = settingsJSONURL
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .notConfigured(reason: I18n.shared.string(.codebuddySetupMissingSettingsJson))
        }

        guard let data = fileManager.contents(atPath: settingsURL.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return .notConfigured(reason: I18n.shared.string(.codebuddySetupInvalidSettingsJson))
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
                    guard let cmd = handler["command"] as? String, !cmd.isEmpty else { continue }
                    // 只认指向本应用桥接脚本的 command，避免用户自己的 hook 被误判为「已配置」。
                    let isLiang = (cmd as NSString).standardizingPath == defaultScriptURL.path
                        || (cmd as NSString).lastPathComponent == "codebuddy-bridge.sh"
                    guard isLiang else { continue }
                    if scriptPath == nil {
                        scriptPath = resolveScriptPath(cmd)
                    }
                    found = true
                    break
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
                .appendingPathComponent(".codebuddy/\(String(cmd.dropFirst(2)))")
                .path
        }
        return (cmd as NSString).standardizingPath
    }

    // MARK: - Install

    private func performInstall() async throws {
        let fileManager = FileManager.default
        logger.info("Starting CodeBuddy Hooks auto-install...")

        // 桥接脚本查找：先 .app bundle（DMG 打包），再 SPM 资源 bundle（本地 debug）。
        // 必须先查 Bundle.main——DMG 未附带 Liang_Liang.bundle 时，访问 Bundle.module 会 fatalError。
        var sourceURL: URL?
        for subdir in ["hooks", nil] {
            if let url = Bundle.main.url(forResource: "codebuddy-bridge", withExtension: "sh", subdirectory: subdir) {
                sourceURL = url
                break
            }
        }
        if sourceURL == nil {
            for subdir in ["Resources/hooks", "hooks", nil] {
                if let url = Bundle.module.url(forResource: "codebuddy-bridge", withExtension: "sh", subdirectory: subdir) {
                    sourceURL = url
                    break
                }
            }
        }
        guard let sourceURL else {
            logger.error("codebuddy-bridge.sh not found in bundle")
            throw CodeBuddySetupError.bridgeScriptNotFoundInBundle
        }

        let hooksDir = defaultScriptURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: defaultScriptURL.path) {
            try fileManager.removeItem(at: defaultScriptURL)
        }
        try fileManager.copyItem(at: sourceURL, to: defaultScriptURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: defaultScriptURL.path)

        // 读取现有 settings.json 并合并，只改 hooks 字段，保留用户既有配置。
        var existingConfig: [String: Any] = [:]
        if let existingData = fileManager.contents(atPath: settingsJSONURL.path) {
            guard let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                throw CodeBuddySetupError.configParseFailed(settingsJSONURL.path)
            }
            existingConfig = json
        }

        var hooks = existingConfig["hooks"] as? [String: Any] ?? [:]
        let scriptPath = defaultScriptURL.path

        for event in requiredHooks {
            let handler: [String: Any] = ["type": "command", "command": scriptPath]
            let groups = hooks[event] as? [[String: Any]] ?? []

            // 移除旧的 Liang 条目（按 command 指向 codebuddy-bridge.sh），保留其他 handler。
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

        logger.info("CodeBuddy Hooks auto-install completed")
    }
}
