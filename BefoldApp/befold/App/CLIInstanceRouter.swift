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
    ///
    /// maxForwardAttempts × ackTimeout(現状 1.5 秒)は、起動直後でオブザーバ登録が
    /// まだ完了していない宛先インスタンスへの転送が待つ最大時間でもある(task-86)。
    /// ここを安易に短縮すると、宛先の初期化がこの総待ち時間より遅い場合に、
    /// 一度も request が届かないまま isDestinationAlive のフォールバックで
    /// 成功扱いされてしまう既知の限界(task-86)を悪化させる。CLI 呼び出し元の
    /// 体感速度より、この安全マージンを優先し現状の値を維持する(task-88)。
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
    ///
    /// ACK 自体も同じ DistributedNotificationCenter 経由で返ってくるため、request 側同様に
    /// 消失しうる。`maxAttempts` 回再送しても ACK が一度も観測できなかった場合、宛先プロセスが
    /// まだ生存していれば「(ほぼ確実に配送されている) request は処理済みだが ACK だけ消失した」と
    /// みなし、配送失敗ではなく成功として扱う(task-81)。宛先プロセスが実際に終了していた場合のみ、
    /// 真の配送失敗として false を返す。
    /// 戻り値は転送が(確認または生存推定により)成功したとみなせるか(false の場合のみ、
    /// 呼び出し元はエラーとして扱うこと)。
    ///
    /// この「宛先生存 = 成功」推定は、次の2ケースでは実際には未処理のまま成功を返しうる
    /// (task-86で検討済み、意図的に許容している既知の限界):
    /// - 起動直後で `AppDelegate.init()` のオブザーバ登録がまだ完了していないインスタンスへの転送
    ///   (task-85 でオブザーバ登録を init() へ前倒しし窓は最小化したが、プロセスが
    ///   `NSRunningApplication` に見え始めてから登録完了までの窓は原理的にゼロにできない)
    /// - 宛先プロセスは生存しているが RunLoop がハングしており通知を処理できない場合
    /// forward() はこの2ケースを「ACK消失だが処理済み」と区別できない。区別するには同期的な
    /// IPC(XPC・ソケットハンドシェイク等)への作り直しが必要で、残るレース窓の狭さに対して
    /// 割に合わないため、現状の推定ベースの設計を維持する。
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
