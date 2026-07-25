import AppKit
import Foundation

/// CLI 起動時、既に起動中の befold インスタンスがあればそちらへファイルオープン要求を転送する。
/// これにより CLI 経由の起動でも、既存インスタンスのウィンドウ管理(セッション・重複オープン抑止等)を
/// そのまま利用でき、`--hidden-files` 等の表示オプションも既存インスタンスへ届けられる。
public enum CLIInstanceRouter {
    public static let openRequestNotificationName = Notification.Name("dev.befold.cli.openRequest")
    public static let openRequestAckNotificationName = Notification.Name("dev.befold.cli.openRequestAck")

    /// 再送の上限回数。maxForwardAttempts × ackTimeout = 10 秒が転送の総予算になる。
    ///
    /// 宛先がコールドローンチ中の場合、NSRunningApplication として検出できてから
    /// ランループが回って通知が配送されるまでには相応の時間がかかる(アップデート直後の
    /// 初回起動・遅いディスクでは特に)。ここが短いと、request が一度も届かないまま
    /// 全試行を使い切ってしまう。CLIAppLauncher がアプリの出現を待つ上限(pollTimeout = 10 秒)
    /// と同じ予算を、届いたことの確認にも与える。
    public static let maxForwardAttempts = 20
    /// 1回の試行あたり、ACK 受信を待つ最大秒数。
    public static let ackTimeout: TimeInterval = 0.5

    /// 起動中の befold.app インスタンスを探す。
    ///
    /// 探索対象のバンドル ID は `Bundle.main` からではなく `AppBundle.identifier` から取る。
    /// befold-cli は `/usr/local/bin/befold` の symlink 経由で起動され、その場合 `Bundle.main` は
    /// symlink の置き場所(`/usr/local/bin`)に解決されて bundleIdentifier が nil になるため。
    @MainActor
    public static func runningInstance(
        runningApplications: (String) -> [NSRunningApplication] = {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
    ) -> NSRunningApplication? {
        runningApplications(AppBundle.identifier)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// `paths`/`options` を既存インスタンスへ Distributed Notification 経由で転送し、
    /// 対象インスタンスからの ACK を待つ。ACK が届くまで `maxAttempts` 回まで再送する。
    ///
    /// ACK の待ち受けは最初の post より前に開始し、再送をまたいで解除しない。
    /// post してから待ち受けを始めると、その間に返った ACK を取りこぼす。宛先が
    /// コールドローンチ中のときはこの取りこぼしが起きやすく、実際には届いていた要求を
    /// 「未達」と誤判定する原因になる。
    ///
    /// ACK を一度も観測できなければ失敗を返す。宛先プロセスの生存は「要求が届いた」ことの
    /// 証拠にはならない(オブザーバ未登録で起動中のインスタンスはまさに生存しているが届かない)。
    /// ここを成功扱いにすると CLI が exit 0 するのにファイルが開かない無言失敗になるため、
    /// 生存によるフォールバックは設けない。再送は GUI 側が requestID で重複排除するため、
    /// 同じファイルが二重に開くことはない。
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
        makeAckWaiter: (String) -> any AckWaiting = { DistributedAckWaiter(requestID: $0) },
        activate: (() -> Void)? = nil
    ) -> Bool {
        let activate = activate ?? { instance.activate() }
        let requestID = UUID().uuidString
        var userInfo: [String: Any] = ["paths": paths, "requestID": requestID]
        if let value = options.showHiddenFiles { userInfo["showHiddenFiles"] = value }
        if let value = options.showLineNumbers { userInfo["showLineNumbers"] = value }
        if let value = options.sourceMode { userInfo["sourceMode"] = value }
        if let value = options.showSidebar { userInfo["showSidebar"] = value }
        if let value = options.sortOrder { userInfo["sortOrder"] = value.rawValue }

        let waiter = makeAckWaiter(requestID)
        defer { waiter.cancel() }

        for _ in 0 ..< maxAttempts {
            post(openRequestNotificationName, userInfo)
            if waiter.wait(timeout: ackTimeout) {
                activate()
                return true
            }
        }
        return false
    }

    /// 受信した Distributed Notification の userInfo から paths/options を復元する。
    public static func decode(userInfo: [AnyHashable: Any]?) -> (paths: [String], options: CLIOpenOptions)? {
        guard let paths = userInfo?["paths"] as? [String] else { return nil }
        var options = CLIOpenOptions()
        options.showHiddenFiles = userInfo?["showHiddenFiles"] as? Bool
        options.showLineNumbers = userInfo?["showLineNumbers"] as? Bool
        options.sourceMode = userInfo?["sourceMode"] as? Bool
        options.showSidebar = userInfo?["showSidebar"] as? Bool
        if let rawSortOrder = userInfo?["sortOrder"] as? String {
            options.sortOrder = CLISortOrderOption(rawValue: rawSortOrder)
        }
        return (paths, options)
    }

    /// 受信した Distributed Notification の userInfo から requestID を取り出す(ACK 送信用)。
    public static func requestID(from userInfo: [AnyHashable: Any]?) -> String? {
        userInfo?["requestID"] as? String
    }

    /// 受信側が要求を受け取ったことを ACK 通知で送り返す。
    public static func sendAck(requestID: String) {
        DistributedNotificationCenter.default().postNotificationName(
            openRequestAckNotificationName, object: nil,
            userInfo: ["requestID": requestID], deliverImmediately: true
        )
    }
}
