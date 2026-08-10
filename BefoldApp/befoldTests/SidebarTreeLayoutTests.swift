@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 「フォルダを開いたまま複数階層を同時表示する」不変条件と、表示モードの永続化
/// (TASK-361.4)。
@Suite
@MainActor
struct SidebarTreeLayoutTests {
    private func folder(_ path: String) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .folder)
    }

    private func file(_ path: String) -> FileListEntry {
        FileListEntry(url: URL(fileURLWithPath: path), kind: .file)
    }

    // MARK: - 不変条件（複数階層の同時表示）

    /// これが本機能の存在理由。片方しか開けない改修が入れば落ちる。
    @Test("兄弟の 2 フォルダを同時に展開すると、両方の子が並ぶ")
    func keepsMultipleFoldersExpandedAtOnce() {
        let dirA = folder("/root/a")
        let dirB = folder("/root/b")
        let childA = file("/root/a/1.md")
        let childB = file("/root/b/2.md")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [dirA, dirB],
            expanded: [dirA.pathKey, dirB.pathKey],
            childrenByPathKey: [dirA.pathKey: [childA], dirB.pathKey: [childB]],
            showsDisclosure: true
        )

        #expect(
            rows.map(\.url.lastPathComponent) == ["a", "1.md", "b", "2.md"]
        )
        #expect(rows.map(\.depth) == [0, 1, 0, 1])
    }

    @Test("展開したが子が未到着のフォルダは、行を増やさず読み込み中の三角になる")
    func loadingFolderShowsIndicatorWithoutRows() {
        let dirA = folder("/root/a")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [dirA], expanded: [],
            childrenByPathKey: [:], loading: [dirA.pathKey], showsDisclosure: true
        )

        #expect(rows.map(\.url.lastPathComponent) == ["a"])
        #expect(rows.first?.disclosure == .loadingChildren)
    }

    /// ドリルダウン側を測る。ツリーを足したことで従来表示の見た目が変わっていないこと
    /// (全行 depth 0・三角なし)は、ここでしか確かめられない。
    @Test("ドリルダウンでは全行 depth 0 で、開閉三角を持たない")
    func drillDownRowsHaveNoDisclosure() {
        let dirA = folder("/root/a")

        let rows = SidebarRowBuilder.rows(
            parentEntry: nil, rootChildren: [dirA, file("/root/b.md")],
            expanded: [], childrenByPathKey: [:]
        )

        #expect(rows.allSatisfy { $0.depth == 0 })
        #expect(rows.allSatisfy { $0.disclosure == nil })
    }

    // MARK: - 表示モードの永続化

    @Test("表示モードは保存され、次回の読み出しで復元される")
    func layoutModePersists() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarTreeLayoutTests-persist")
        let first = SidebarDisplayPreference(defaults: defaults, isTreeLayoutAvailable: true)
        #expect(first.layoutMode == .drillDown)

        first.layoutMode = .tree

        let restored = SidebarDisplayPreference(defaults: defaults, isTreeLayoutAvailable: true)
        #expect(restored.layoutMode == .tree)
    }

    /// 機能が無効なビルドでは降格して読むが、**保存値は書き換えない**。
    /// init 内の代入では didSet が走らないことに依存しているので、そこを固定する
    /// (showChangedFilesOnly / TASK-284 と同じ形)。
    @Test("ゲート無効ならドリルダウンとして読むが、保存値は書き換えない")
    func gateDowngradesWithoutOverwritingStoredValue() {
        let defaults = makeIsolatedDefaults(prefix: "SidebarTreeLayoutTests-gate")
        let enabled = SidebarDisplayPreference(defaults: defaults, isTreeLayoutAvailable: true)
        enabled.layoutMode = .tree

        let gated = SidebarDisplayPreference(defaults: defaults, isTreeLayoutAvailable: false)
        #expect(gated.layoutMode == .drillDown)

        // dev ビルドへ戻ればツリーのまま復帰する。
        let reenabled = SidebarDisplayPreference(defaults: defaults, isTreeLayoutAvailable: true)
        #expect(reenabled.layoutMode == .tree)
    }

    @Test("保存値が無い・壊れているときはドリルダウンへ倒す")
    func unknownStoredValueFallsBackToDrillDown() {
        #expect(SidebarLayoutMode.stored(nil) == .drillDown)
        #expect(SidebarLayoutMode.stored("nonsense") == .drillDown)
        #expect(SidebarLayoutMode.stored("tree") == .tree)
    }
}
