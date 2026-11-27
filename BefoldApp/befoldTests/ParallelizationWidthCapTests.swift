import BefoldTestSupport
import Foundation
import Testing

/// CI の thread-sanitizer ジョブは `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH` で
/// 同時に走るテストの数を抑える(TASK-933)。窓を作るテストが一斉に窓を開くと、
/// AppKit の描き直しが生きている窓の数に比例して重くなり、全体が制限時間を超えるため。
///
/// 変数名は experimental で、toolchain の更新で黙って効かなくなりうる。そのとき
/// このテストが落ちる。変数が設定された実行でだけ働く。
@Suite
struct ParallelizationWidthCapTests {
    private static let cap = ProcessInfo.processInfo
        .environment["SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH"].flatMap(Int.init)
    private static let inFlight = LockedBox((current: 0, peak: 0))

    @Test("並列幅の上限を設定した実行では、同時に走るケースがその数を超えない", .enabled(if: cap != nil), arguments: 0 ..< 16)
    func concurrentCasesStayWithinCap(index _: Int) async throws {
        let cap = try #require(Self.cap)
        Self.inFlight.update { $0.current += 1; $0.peak = max($0.peak, $0.current) }
        try await Task.sleep(for: .milliseconds(200))
        Self.inFlight.update { $0.current -= 1 }
        #expect(Self.inFlight.get().peak <= cap)
    }
}
