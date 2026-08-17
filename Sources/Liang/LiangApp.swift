import SwiftUI
import AppKit

@main
struct LiangApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        // 用 NSStatusBar 手动管理图标，这里只保留 SwiftUI App 生命周期，不显示默认图标
        MenuBarExtra("Liang", systemImage: "circle.fill", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}
