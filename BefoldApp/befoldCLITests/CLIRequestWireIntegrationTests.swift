@testable import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// ワイヤ表現が実際の DistributedNotificationCenter を通っても壊れないことを検証する。
///
/// userInfo はプロセス境界を越える際に plist 表現へ直列化されるため、載せられる値は
/// plist で表せるものに限られる。要求本体を JSON 文字列にしているのはそのためで、
/// ここで実際の配送を通した往復を確認する(単体の encode/decode 検証は CLIRequestWireTests)。
///
/// 通知名は本番の値ではなくテスト専用の名前を使う。本番の名前で post すると、開発機で
/// 起動中の befold.app が要求を受け取ってファイルを開いてしまうため。
/// 配送が来ないまま待ち続ける退行で実行が止まらないよう、待機予算の単一情報源から
/// スイート全体のタイムリミットを与える。
@Suite(testTimeLimit())
struct CLIRequestWireIntegrationTests {
    private static let testNotificationName = Notification.Name("dev.befold.test.cliRequestWire")

    @Test("全オプション付きの要求が実際の Distributed Notification を通って復元できる")
    func openRequestSurvivesDistributedNotification() async throws {
        let options = CLIOpenOptions(
            showHiddenFiles: true, sortOrder: .alphabetical, showLineNumbers: false,
            sourceMode: true, showSidebar: false
        )
        let request = CLIRequest.open(paths: ["/tmp/a.mmd", "/tmp/b.md"], options: options)
        let userInfo = try #require(
            CLIRequestWire.userInfo(for: request, requestID: "integration-id")
        )

        let received = LockedBox<[String: String]?>(nil)
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: Self.testNotificationName, object: nil, queue: .main
        ) { notification in
            // 配送された userInfo を Sendable な形(全て String)に写して受け渡す。
            received.set(notification.userInfo?.reduce(into: [String: String]()) { result, entry in
                if let key = entry.key as? String, let value = entry.value as? String {
                    result[key] = value
                }
            })
        }
        defer { center.removeObserver(observer) }

        center.postNotificationName(
            Self.testNotificationName, object: nil, userInfo: userInfo, deliverImmediately: true
        )
        #expect(await waitUntil { received.get() != nil }, "テスト通知が配送されなかった")

        let delivered = try #require(received.get())
        #expect(CLIRequestWire.decode(userInfo: delivered) == request)
        #expect(CLIRequestWire.requestID(from: delivered) == "integration-id")
    }
}
