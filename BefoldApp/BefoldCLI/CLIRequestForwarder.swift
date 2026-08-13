import AppKit
import Foundation

/// CLI 起動時、既に起動中の befold インスタンスがあればそちらへ要求を転送する。
/// これにより CLI 経由の起動でも、既存インスタンスのウィンドウ管理(セッション・重複オープン抑止等)を
/// そのまま利用でき、`--hidden-files` 等の表示オプションも既存インスタンスへ届けられる。
///
/// ブックマーク追加も同じ経路に載せる。ブックマークは UserDefaults の配列を
/// read-modify-write で更新するため、CLI と GUI が別プロセスから同時に書くと
/// 後勝ちで片方の追加が消える。起動中インスタンスがあるときは常に GUI プロセスを
/// 唯一の writer にすることで、この競合自体を無くしている。
///
/// 宛先の探索・再送・ACK の busy-wait は送信側だけの関心なので、受信側(befold.app)が
/// リンクしない CLI 実行ファイル側に置く。ワイヤ表現は BefoldCLI の CLIRequestWire が持つ。
public enum CLIRequestForwarder {
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
        post: (Notification.Name, [String: Any]) -> Void = broadcast,
        makeAckWaiter: (String) -> any AckWaiting = { DistributedAckWaiter(requestID: $0) },
        activate: (() -> Void)? = nil
    ) async -> Bool {
        let activate = activate ?? { instance.activate() }
        guard await postAwaitingAck(
            .open(paths: paths, options: options),
            maxAttempts: maxAttempts, ackTimeout: ackTimeout,
            post: post, makeAckWaiter: makeAckWaiter
        ) else { return false }
        activate()
        return true
    }

    /// `paths` のブックマーク追加を既存インスタンスへ転送し、ACK を待つ。
    ///
    /// 転送に成功した場合、ブックマークを実際に書くのは GUI プロセスのみになる。
    /// ACK が届かなければ CLI 側で書き足すのではなく失敗を返す。ここでローカル書き込みへ
    /// フォールバックすると、要求が遅れて届いた GUI との二重書き込みが起き、
    /// この経路で防いでいる read-modify-write 競合が復活するため。
    ///
    /// オープン要求と違いユーザーは GUI を見ていないので、成功しても前面化はしない。
    /// 宛先の指定は不要(通知はブロードキャストで、単一インスタンスの GUI だけが受け取る)だが、
    /// 呼び出し側は起動中インスタンスの存在を確認してから使うこと。居なければ ACK は返らない。
    @MainActor
    public static func forwardBookmark(
        paths: [String],
        maxAttempts: Int = maxForwardAttempts,
        ackTimeout: TimeInterval = ackTimeout,
        post: (Notification.Name, [String: Any]) -> Void = broadcast,
        makeAckWaiter: (String) -> any AckWaiting = { DistributedAckWaiter(requestID: $0) }
    ) async -> Bool {
        await postAwaitingAck(
            .bookmark(paths: paths),
            maxAttempts: maxAttempts, ackTimeout: ackTimeout,
            post: post, makeAckWaiter: makeAckWaiter
        )
    }

    /// requestID を採番して要求をワイヤ表現へ載せ、ACK が観測できるまで最大 `maxAttempts` 回 post する。
    @MainActor
    private static func postAwaitingAck(
        _ request: CLIRequest,
        maxAttempts: Int,
        ackTimeout: TimeInterval,
        post: (Notification.Name, [String: Any]) -> Void,
        makeAckWaiter: (String) -> any AckWaiting
    ) async -> Bool {
        let requestID = UUID().uuidString
        guard let userInfo = CLIRequestWire.userInfo(for: request, requestID: requestID) else {
            return false
        }

        let waiter = makeAckWaiter(requestID)
        defer { waiter.cancel() }

        for _ in 0 ..< maxAttempts {
            post(CLIRequestWire.requestNotificationName, userInfo)
            if await waiter.wait(timeout: ackTimeout) { return true }
        }
        return false
    }

    /// 既定の post 実装(Distributed Notification のブロードキャスト)。テストは post を差し替える。
    public static func broadcast(_ name: Notification.Name, _ userInfo: [String: Any]) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: userInfo, deliverImmediately: true
        )
    }
}
