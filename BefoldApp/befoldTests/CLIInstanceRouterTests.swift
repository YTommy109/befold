import AppKit
@testable import befold
@testable import BefoldCLI
import Foundation
import Testing

/// forward() の ACK 待ち・再送ロジックを、実際の DistributedNotificationCenter を使わず検証する。
/// 起動直後(オブザーバ未登録)のインスタンスへの転送は、post と ACK 待ち受けを差し替えることで
/// 「初回は届かず、後続の再送で届く」「一度も届かない」というタイミングを決定的に再現する。
@Suite
@MainActor
struct CLIInstanceRouterTests {
    @Test("ACK が初回で届いた場合は true を返し、再送せず前面化する")
    func returnsTrueOnFirstAck() {
        var postCount = 0
        var activateCount = 0
        let acked = CLIInstanceRouter.forward(
            paths: ["a.md"], options: CLIOpenOptions(), to: NSRunningApplication.current,
            post: { _, _ in postCount += 1 },
            makeAckWaiter: { _ in StubAckWaiter(ackOnWait: 1) },
            activate: { activateCount += 1 }
        )

        #expect(acked)
        #expect(postCount == 1)
        #expect(activateCount == 1)
    }

    @Test("起動直後でACKが届かない場合、maxAttempts回まで同じ requestID で再送する")
    func retriesWithSameRequestIDUntilAckObserved() {
        var attempts = 0
        var seenRequestIDs: [String] = []
        let acked = CLIInstanceRouter.forward(
            paths: ["a.md"], options: CLIOpenOptions(), to: NSRunningApplication.current,
            maxAttempts: 3,
            post: { _, userInfo in
                attempts += 1
                if let requestID = userInfo["requestID"] as? String { seenRequestIDs.append(requestID) }
            },
            makeAckWaiter: { _ in StubAckWaiter(ackOnWait: 3) }
        )

        #expect(acked)
        #expect(attempts == 3)
        #expect(Set(seenRequestIDs).count == 1)
    }

    /// ACK 待ち受けを post のたびに登録・解除すると、post 直後〜登録前と再送の合間に
    /// ACK を取りこぼす窓ができる。宛先がコールドローンチ中のときはこの窓に当たりやすく、
    /// 実際には届いていた要求を「未達」と誤判定する原因になる。
    /// 待ち受けは最初の post より前に 1 度だけ開始し、全再送を通じて解除しないことを規定する。
    @Test("ACK 待ち受けは最初の post より前に開始され、再送の合間に解除されない")
    func ackWaiterIsArmedBeforeFirstPostAndKeptAcrossRetries() {
        var events: [String] = []
        var waiterCount = 0

        let acked = CLIInstanceRouter.forward(
            paths: ["a.md"], options: CLIOpenOptions(), to: NSRunningApplication.current,
            maxAttempts: 3,
            post: { _, _ in events.append("post") },
            makeAckWaiter: { _ in
                waiterCount += 1
                events.append("arm")
                return StubAckWaiter(ackOnWait: 3) { events.append($0) }
            },
            activate: {}
        )

        #expect(acked)
        // 待ち受けの開始は 1 度だけ、かつ最初の post より前。
        #expect(waiterCount == 1)
        #expect(events.first == "arm")
        // 解除は全再送を終えた後の 1 度だけ(post と post の間に cancel が挟まらない)。
        #expect(events.count(where: { $0 == "cancel" }) == 1)
        #expect(events == ["arm", "post", "wait", "post", "wait", "post", "wait", "cancel"])
    }

    /// 宛先が生存していても、ACK が一度も観測できなければ「届いた」ことは確認できていない。
    /// コールドローンチ中でオブザーバ未登録のインスタンスがまさにこの状態であり、
    /// ここを成功扱いにすると CLI は exit 0 するのにファイルが開かない無言失敗になる。
    @Test("ACK が一度も届かなければ失敗を返し、前面化もしない")
    func returnsFalseWhenAckNeverObserved() {
        var attempts = 0
        var activateCount = 0
        let acked = CLIInstanceRouter.forward(
            paths: ["a.md"], options: CLIOpenOptions(), to: NSRunningApplication.current,
            maxAttempts: 3,
            post: { _, _ in attempts += 1 },
            makeAckWaiter: { _ in StubAckWaiter(ackOnWait: 0) },
            activate: { activateCount += 1 }
        )

        #expect(!acked)
        #expect(attempts == 3)
        #expect(activateCount == 0)
    }

    /// befold-cli は `/usr/local/bin/befold` の symlink 経由で起動されるため、Bundle.main は
    /// symlink の置き場所(`/usr/local/bin`)に解決され bundleIdentifier は nil になる。
    /// 起動中インスタンスの探索を Bundle.main に依存させてはならない。
    @Test("runningInstance は Bundle.main のバンドル ID ではなく befold.app のバンドル ID で探索する")
    func runningInstanceLooksUpAppBundleIdentifier() {
        var queried: [String] = []
        _ = CLIInstanceRouter.runningInstance(runningApplications: { identifier in
            queried.append(identifier)
            return []
        })

        #expect(queried == [AppBundle.identifier])
    }

    @Test("requestID / decode は往復できる")
    func requestIDRoundTrips() {
        let userInfo: [AnyHashable: Any] = ["paths": ["a.md"], "requestID": "abc-123"]

        #expect(CLIInstanceRouter.requestID(from: userInfo) == "abc-123")
        #expect(CLIInstanceRouter.decode(userInfo: userInfo) == .open(paths: ["a.md"], options: CLIOpenOptions()))
    }

    // MARK: - ブックマーク転送

    /// ブックマークの書き込みプロセスを GUI に一本化するため、CLI は起動中インスタンスへ
    /// 要求を転送する。転送された userInfo が受信側で .bookmark として復元できることを規定する。
    @Test("forwardBookmark は bookmarkPaths として post され、decode でブックマーク要求に戻る")
    func forwardBookmarkPostsBookmarkPaths() {
        var posted: [String: Any] = [:]
        let acked = CLIInstanceRouter.forwardBookmark(
            paths: ["/tmp/a.md"],
            post: { _, userInfo in posted = userInfo },
            makeAckWaiter: { _ in StubAckWaiter(ackOnWait: 1) }
        )

        #expect(acked)
        #expect(CLIInstanceRouter.decode(userInfo: posted) == .bookmark(paths: ["/tmp/a.md"]))
        #expect(CLIInstanceRouter.requestID(from: posted) != nil)
    }

    @Test("forwardBookmark も ACK が届くまで同じ requestID で再送する")
    func forwardBookmarkRetriesWithSameRequestID() {
        var seenRequestIDs: [String] = []
        let acked = CLIInstanceRouter.forwardBookmark(
            paths: ["/tmp/a.md"],
            maxAttempts: 3,
            post: { _, userInfo in
                if let requestID = userInfo["requestID"] as? String { seenRequestIDs.append(requestID) }
            },
            makeAckWaiter: { _ in StubAckWaiter(ackOnWait: 3) }
        )

        #expect(acked)
        #expect(seenRequestIDs.count == 3)
        #expect(Set(seenRequestIDs).count == 1)
    }

    @Test("forwardBookmark は ACK が一度も届かなければ失敗を返す")
    func forwardBookmarkReturnsFalseWhenAckNeverObserved() {
        var attempts = 0
        let acked = CLIInstanceRouter.forwardBookmark(
            paths: ["/tmp/a.md"],
            maxAttempts: 3,
            post: { _, _ in attempts += 1 },
            makeAckWaiter: { _ in StubAckWaiter(ackOnWait: 0) }
        )

        #expect(!acked)
        #expect(attempts == 3)
    }
}
