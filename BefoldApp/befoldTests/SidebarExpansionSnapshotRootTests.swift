@testable import befold
import Foundation
import Testing

/// ツリー⇄リスト切り替えで覚えるスナップショット root(TASK-481)。境界は
/// **展開の世代ガードとデータを共有しない**こと——扱うのは `snapshotRoot` と
/// `snapshotRootCovers` だけで、券も children も出てこない。展開そのものの規則は
/// `SidebarExpansionTests`、列挙失敗の 3 値は `SidebarExpansionFailureTests` にある。
@Suite
@MainActor
struct SidebarExpansionSnapshotRootTests {
    private let root = URL(fileURLWithPath: "/tmp/SidebarExpansionSnapshotRootTests")

    /// ツリー→リスト切り替え時のルートを 1 つだけ覚える。展開集合そのものは
    /// コピーせず生かしたまま残すので、スナップショットは root URL だけでよい。
    @Test("記録したスナップショット root を読み出せる")
    func recordsSnapshotRoot() {
        let expansion = SidebarExpansion()
        #expect(expansion.snapshotRoot == nil)

        expansion.recordSnapshotRoot(root)
        #expect(expansion.snapshotRoot == root)

        expansion.clearSnapshotRoot()
        #expect(expansion.snapshotRoot == nil)
    }

    /// スナップショットは展開集合と同じ寿命。ルート切り替えで展開を捨てたのに
    /// root だけが残ると、次のリスト→ツリー切り替えが別ツリーの root へ引き戻す。
    @Test("invalidateAll はスナップショット root も必ず捨てる")
    func invalidateAllClearsSnapshotRoot() {
        let expansion = SidebarExpansion()
        expansion.recordSnapshotRoot(root)

        expansion.invalidateAll()

        #expect(expansion.snapshotRoot == nil)
    }

    /// 配下判定は collapse の波及と同じ規則（区切り文字を含めた前方一致）を共有する。
    /// 区切りを含めないと /…/ab が /…/a の配下と誤判定される（collapse の兄弟テストと同型）。
    @Test("スナップショット root の配下判定は自身を含み、兄弟パスと上位を含まない")
    func snapshotRootCoverageMatchesCollapseRule() {
        let expansion = SidebarExpansion()
        expansion.recordSnapshotRoot(root.appendingPathComponent("a"))

        #expect(expansion.snapshotRootCovers(root.appendingPathComponent("a")))
        #expect(expansion.snapshotRootCovers(root.appendingPathComponent("a/b")))
        #expect(!expansion.snapshotRootCovers(root.appendingPathComponent("ab")))
        #expect(!expansion.snapshotRootCovers(root))
    }

    /// スナップショットが無いときは何も覆わない（復元しない側に倒す）。
    @Test("スナップショット root が無ければ配下判定は常に false")
    func coverageIsFalseWithoutSnapshotRoot() {
        let expansion = SidebarExpansion()
        #expect(!expansion.snapshotRootCovers(root))
    }
}
