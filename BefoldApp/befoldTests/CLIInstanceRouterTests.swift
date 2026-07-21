import AppKit
@testable import befold
import Foundation
import Testing

/// TASK-73.6: forward() の ACK 待ち・再送ロジックを、実際の DistributedNotificationCenter を使わず検証する。
/// 起動直後(オブザーバ未登録)のインスタンスへの転送は、post/waitForAck を差し替えることで
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
            waitForAck: { _, _ in true },
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
            waitForAck: { _, _ in attempts >= 3 }
        )

        #expect(acked)
        #expect(attempts == 3)
        #expect(Set(seenRequestIDs).count == 1)
    }

    @Test("maxAttempts回試してもACKが届かず、かつ宛先プロセスが終了している場合は false を返す(真の配送失敗)")
    func returnsFalseWhenAckNeverObservedAndDestinationTerminated() {
        var attempts = 0
        var activateCount = 0
        let acked = CLIInstanceRouter.forward(
            paths: ["a.md"], options: CLIOpenOptions(), to: NSRunningApplication.current,
            maxAttempts: 3,
            post: { _, _ in attempts += 1 },
            waitForAck: { _, _ in false },
            isDestinationAlive: { false },
            activate: { activateCount += 1 }
        )

        #expect(!acked)
        #expect(attempts == 3)
        #expect(activateCount == 0)
    }

    @Test("maxAttempts回試してもACKが届かないが、宛先プロセスが生存している場合はACK消失とみなし true を返し前面化する(task-81)")
    func returnsTrueWhenAckLostButDestinationAlive() {
        var attempts = 0
        var activateCount = 0
        let acked = CLIInstanceRouter.forward(
            paths: ["a.md"], options: CLIOpenOptions(), to: NSRunningApplication.current,
            maxAttempts: 3,
            post: { _, _ in attempts += 1 },
            waitForAck: { _, _ in false },
            isDestinationAlive: { true },
            activate: { activateCount += 1 }
        )

        #expect(acked)
        #expect(attempts == 3)
        #expect(activateCount == 1)
    }

    @Test("requestID / decode は往復できる")
    func requestIDRoundTrips() {
        let userInfo: [AnyHashable: Any] = ["paths": ["a.md"], "requestID": "abc-123"]

        #expect(CLIInstanceRouter.requestID(from: userInfo) == "abc-123")
        #expect(CLIInstanceRouter.decode(userInfo: userInfo)?.paths == ["a.md"])
    }
}
