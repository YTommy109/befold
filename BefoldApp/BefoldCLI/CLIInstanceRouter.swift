import AppKit
import Foundation

public enum CLIInstanceRouter {
    public static let openRequestNotificationName = Notification.Name("dev.befold.cli.openRequest")
    public static let openRequestAckNotificationName = Notification.Name("dev.befold.cli.openRequestAck")

    public static let maxForwardAttempts = 3
    /// 1回の試行あたり、ACK 受信を待つ最大秒数。
    ///
    /// maxForwardAttempts × ackTimeout(現状 1.5 秒)は、起動直後でオブザーバ登録が
    /// まだ完了していない宛先インスタンスへの転送が待つ最大時間でもある(task-86)。
    /// ここを安易に短縮すると、宛先の初期化がこの総待ち時間より遅い場合に、
    /// 一度も request が届かないまま isDestinationAlive のフォールバックで
    /// 成功扱いされてしまう既知の限界(task-86)を悪化させる。CLI 呼び出し元の
    /// 体感速度より、この安全マージンを優先し現状の値を維持する(task-88)。
    public static let ackTimeout: TimeInterval = 0.5

    @MainActor
    public static func runningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// `paths`/`options` を既存インスタンスへ Distributed Notification 経由で転送し、
    /// 対象インスタンスからの ACK を待つ。ACK が届くまで `maxAttempts` 回まで再送する。
    ///
    /// ACK も DistributedNotificationCenter 経由のため消失しうる。全試行で ACK 未観測でも
    /// 宛先プロセスが生存していれば成功として扱う(task-81)。
    @MainActor
    public static func forward(
        paths: [String], options: CLIOpenOptions, to instance: NSRunningApplication,
        maxAttempts: Int = maxForwardAttempts,
        ackTimeout: TimeInterval = ackTimeout,
        post: (Notification.Name, [String: Any]) -> Void = { name, userInfo in
            DistributedNotificationCenter.default().postNotificationName(
                name, object: nil, userInfo: userInfo, deliverImmediately: true
            )
        },
        waitForAck: (String, TimeInterval) -> Bool = defaultWaitForAck,
        isDestinationAlive: (() -> Bool)? = nil,
        activate: (() -> Void)? = nil
    ) -> Bool {
        let isDestinationAlive = isDestinationAlive ?? { !instance.isTerminated }
        let activate = activate ?? { instance.activate() }
        let requestID = UUID().uuidString
        var userInfo: [String: Any] = ["paths": paths, "requestID": requestID]
        if let value = options.showHiddenFiles { userInfo["showHiddenFiles"] = value }
        if let value = options.showLineNumbers { userInfo["showLineNumbers"] = value }
        if let value = options.sourceMode { userInfo["sourceMode"] = value }
        if let value = options.sortOrder { userInfo["sortOrder"] = value.rawValue }

        for _ in 0 ..< maxAttempts {
            post(openRequestNotificationName, userInfo)
            if waitForAck(requestID, ackTimeout) {
                activate()
                return true
            }
        }
        guard isDestinationAlive() else { return false }
        activate()
        return true
    }

    public static func defaultWaitForAck(requestID: String, timeout: TimeInterval) -> Bool {
        var acked = false
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: openRequestAckNotificationName, object: nil, queue: nil
        ) { notification in
            if notification.userInfo?["requestID"] as? String == requestID { acked = true }
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        let deadline = Date().addingTimeInterval(timeout)
        while !acked, Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.02)))
        }
        return acked
    }

    public static func decode(userInfo: [AnyHashable: Any]?) -> (paths: [String], options: CLIOpenOptions)? {
        guard let paths = userInfo?["paths"] as? [String] else { return nil }
        var options = CLIOpenOptions()
        options.showHiddenFiles = userInfo?["showHiddenFiles"] as? Bool
        options.showLineNumbers = userInfo?["showLineNumbers"] as? Bool
        options.sourceMode = userInfo?["sourceMode"] as? Bool
        if let rawSortOrder = userInfo?["sortOrder"] as? String {
            options.sortOrder = CLISortOrderOption(rawValue: rawSortOrder)
        }
        return (paths, options)
    }

    public static func requestID(from userInfo: [AnyHashable: Any]?) -> String? {
        userInfo?["requestID"] as? String
    }

    public static func sendAck(requestID: String) {
        DistributedNotificationCenter.default().postNotificationName(
            openRequestAckNotificationName, object: nil,
            userInfo: ["requestID": requestID], deliverImmediately: true
        )
    }
}
