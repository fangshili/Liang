import Foundation

/// 多 IDE 适配器协议。T9 阶段只接入 Cursor，其他 IDE 通过此协议预留扩展点。
protocol IDEAdapter: AnyObject {
    /// 所属 IDE。
    var id: IDE { get }

    /// 是否正在监听事件。
    var isRunning: Bool { get }

    /// 当前是否与 IDE 事件源保持连接。
    var isConnected: Bool { get }

    /// 最近一次错误（如有）。
    var lastError: Error? { get }

    /// 开始监听。
    func start()

    /// 停止监听。
    func stop()
}
