import AppKit
import Foundation

/// CLI 起動時、既に起動中の befold インスタンスがあればそちらへファイルオープン要求を転送する。
/// これにより CLI 経由の起動でも、既存インスタンスのウィンドウ管理(セッション・重複オープン抑止等)を
/// そのまま利用でき、`--hidden-files` 等の表示オプションも既存インスタンスへ届けられる。
enum CLIInstanceRouter {
    /// `DistributedNotificationCenter` 経由でオープン要求を伝える通知名。
    static let openRequestNotificationName = Notification.Name("dev.befold.cli.openRequest")
    /// 受信側が要求を受け取ったことを伝える通知名(受信確認)。
    static let openRequestAckNotificationName = Notification.Name("dev.befold.cli.openRequestAck")

    /// forward() が ACK 未受信時に同じ要求を再送する最大試行回数。
    static let maxForwardAttempts = 3
    /// 1回の試行あたり、ACK 受信を待つ最大秒数。
    static let ackTimeout: TimeInterval = 0.5

    /// 自プロセス以外に起動中の befold インスタンスがあれば返す。
    @MainActor
    static func runningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// `paths`/`options` を既存インスタンスへ Distributed Notification 経由で転送し、
    /// 対象インスタンスからの ACK を待つ。起動直後でオブザーバ未登録のインスタンスへ転送する場合、
    /// 通知は誰にも受信されず失われうるため、ACK が届くまで `maxAttempts` 回まで再送する。
    /// 戻り値は ACK を確認できたかどうか(false の場合、呼び出し元はエラーとして扱うこと)。
    @MainActor
    static func forward(
        paths: [String], options: CLIOpenOptions, to instance: NSRunningApplication,
        maxAttempts: Int = maxForwardAttempts,
        ackTimeout: TimeInterval = ackTimeout,
        post: (Notification.Name, [String: Any]) -> Void = { name, userInfo in
            DistributedNotificationCenter.default().postNotificationName(
                name, object: nil, userInfo: userInfo, deliverImmediately: true
            )
        },
        waitForAck: (String, TimeInterval) -> Bool = defaultWaitForAck
    ) -> Bool {
        let requestID = UUID().uuidString
        var userInfo: [String: Any] = ["paths": paths, "requestID": requestID]
        if let value = options.showHiddenFiles { userInfo["showHiddenFiles"] = value }
        if let value = options.showLineNumbers { userInfo["showLineNumbers"] = value }
        if let value = options.sourceMode { userInfo["sourceMode"] = value }
        if let value = options.sortOrder { userInfo["sortOrder"] = value.rawValue }

        for _ in 0 ..< maxAttempts {
            post(openRequestNotificationName, userInfo)
            if waitForAck(requestID, ackTimeout) {
                instance.activate()
                return true
            }
        }
        return false
    }

    /// `openRequestAckNotificationName` を購読し、一致する requestID の ACK を `timeout` 秒まで待つ。
    private static func defaultWaitForAck(requestID: String, timeout: TimeInterval) -> Bool {
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

    /// 受信した Distributed Notification の userInfo から paths/options を復元する。
    static func decode(userInfo: [AnyHashable: Any]?) -> (paths: [String], options: CLIOpenOptions)? {
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

    /// 受信した Distributed Notification の userInfo から requestID を取り出す(ACK 送信用)。
    static func requestID(from userInfo: [AnyHashable: Any]?) -> String? {
        userInfo?["requestID"] as? String
    }

    /// 受信側が要求を受け取ったことを ACK 通知で送り返す。
    static func sendAck(requestID: String) {
        DistributedNotificationCenter.default().postNotificationName(
            openRequestAckNotificationName, object: nil,
            userInfo: ["requestID": requestID], deliverImmediately: true
        )
    }
}
