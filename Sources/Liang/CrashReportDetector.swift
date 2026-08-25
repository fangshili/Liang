import Foundation
import AppKit

/// 检测用户上次使用 Liang 时是否发生崩溃，并定位 macOS 系统生成的崩溃日志。
/// 复用系统自带的崩溃报告（`~/Library/Logs/DiagnosticReports/Liang-*.ips`），
/// 不自动上传、不读取日志内容，只在下次启动时提示用户「上次崩溃了」并引导其在 Finder 中定位日志文件。
@MainActor
final class CrashReportDetector: ObservableObject {
    static let shared = CrashReportDetector()

    /// 最新一次崩溃日志的 URL；nil 表示没有检测到新崩溃。
    @Published private(set) var latestCrashReportURL: URL?

    private let lastCheckKey = "com.liang.lastCrashReportCheckDate"

    private var reportsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    private init() {}

    /// 启动时调用：扫描「上次检查之后」新增的 Liang 崩溃日志。
    func check() {
        let defaults = UserDefaults.standard
        let now = Date()
        // 每次检查后都把「当前时间」记为新的基线，下次只认之后的新日志。
        defer { defaults.set(now, forKey: lastCheckKey) }

        // 首次运行（无基线）：只记录时间不扫描，避免把升级前的历史崩溃误报为新崩溃。
        guard let lastCheck = defaults.object(forKey: lastCheckKey) as? Date else { return }

        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: reportsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let newReports = files
            .filter { $0.lastPathComponent.hasPrefix("Liang-") && $0.pathExtension == "ips" }
            .filter { url in
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return mod > lastCheck
            }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }

        latestCrashReportURL = newReports.first
    }

    /// 在 Finder 中定位并选中最新的崩溃日志文件。
    func revealInFinder() {
        guard let url = latestCrashReportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
