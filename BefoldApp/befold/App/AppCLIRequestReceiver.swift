import AppKit
import BefoldCLI

/// 別プロセスの CLI 起動から、起動中の当インスタンスへ転送された要求を受け取る。
///
/// **購読は生成と同時に始まる。** 生成を遅らせる(lazy にする・`applicationDidFinishLaunching`
/// で組み立てる)と、起動と同時に届いた要求の ACK を取りこぼし、`CLIRequestForwarder` の
/// 再送を待たせることになる。AppDelegate の `init` 内で eager に生成すること。
@MainActor
final class AppCLIRequestReceiver: NSObject {
    private let onOpen: @MainActor ([String], CLIOpenOptions) -> Void
    private let onBookmark: @MainActor ([URL]) -> Void
    private var deduplicator = CLIRequestDeduplicator()

    /// - Parameters:
    ///   - onOpen: `--` 付きの表示オプションを伴うパス群を開く先。
    ///   - onBookmark: ブックマーク追加の反映先。
    init(
        onOpen: @escaping @MainActor ([String], CLIOpenOptions) -> Void,
        onBookmark: @escaping @MainActor ([URL]) -> Void
    ) {
        self.onOpen = onOpen
        self.onBookmark = onBookmark
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleRequest(_:)),
            name: CLIRequestWire.requestNotificationName, object: nil
        )
    }

    /// forward() は ACK 未受信時に同じ requestID で再送するため、ACK は受信のたびに返すが、
    /// 要求の実行は requestID ごとに一度だけに絞る。
    ///
    /// ブックマーク追加を CLI プロセスではなくここで行うことで、UserDefaults の
    /// ブックマーク配列を書くプロセスを GUI に一本化し、CLI との同時更新で
    /// 片方の追加が消える競合を防ぐ(CLIRequestForwarder 参照)。
    @objc private func handleRequest(_ notification: Notification) {
        guard let request = CLIRequestWire.decode(userInfo: notification.userInfo) else { return }
        let requestID = CLIRequestWire.requestID(from: notification.userInfo)
        if let requestID {
            CLIRequestWire.sendAck(requestID: requestID)
        }
        guard deduplicator.shouldProcess(requestID: requestID) else { return }
        switch request {
        case let .open(paths, options):
            onOpen(paths, options)
            NSApp.activate()
        case let .bookmark(paths):
            // ユーザーは GUI を見ていないので前面化はしない。
            onBookmark(paths.map { URL(fileURLWithPath: $0) })
        }
    }
}
