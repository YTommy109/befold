@testable import befold
import Testing

/// CLIInstanceRouter.forward() の再送による同一requestIDの二重処理防止(task-79)を検証する。
/// 実際の DistributedNotificationCenter には依存せず、requestID の重複判定だけを純粋に検証する。
@Suite
struct CLIRequestDeduplicatorTests {
    @Test("同一requestIDは最初の一回だけ true を返す")
    func sameRequestIDIsProcessedOnlyOnce() {
        var deduplicator = CLIRequestDeduplicator()

        let first = deduplicator.shouldProcess(requestID: "req-1")
        let second = deduplicator.shouldProcess(requestID: "req-1")
        let third = deduplicator.shouldProcess(requestID: "req-1")

        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test("異なるrequestIDはそれぞれ独立して true を返す")
    func differentRequestIDsAreIndependent() {
        var deduplicator = CLIRequestDeduplicator()

        let req1First = deduplicator.shouldProcess(requestID: "req-1")
        let req2First = deduplicator.shouldProcess(requestID: "req-2")
        let req1Second = deduplicator.shouldProcess(requestID: "req-1")

        #expect(req1First)
        #expect(req2First)
        #expect(!req1Second)
    }

    @Test("requestID が nil の場合は常に true を返す")
    func nilRequestIDAlwaysProcesses() {
        var deduplicator = CLIRequestDeduplicator()

        let first = deduplicator.shouldProcess(requestID: nil)
        let second = deduplicator.shouldProcess(requestID: nil)

        #expect(first)
        #expect(second)
    }
}
