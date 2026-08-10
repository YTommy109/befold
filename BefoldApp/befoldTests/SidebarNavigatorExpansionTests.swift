@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// SidebarNavigator へ配線した展開の世代ガード(TASK-361.3)。
///
/// 競合は固定 sleep ではなく AsyncGate で 1 つ目の子リスト列挙を明示的に足止めしてから
/// 2 つ目を発行することで、タイミング依存なく決定的に再現する
/// (SidebarNavigatorGenerationTests と同じ手法)。
@Suite
@MainActor
struct SidebarNavigatorExpansionTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private func makeNavigator(
        currentDirectory: URL,
        rootEntries: [FileListEntry],
        childrenLister: @escaping @Sendable (URL, befold.SortOrder, Bool) async -> [FileListEntry]?
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        // 展開はツリー表示のときだけ行に出る。ドリルダウンでは展開の材料を渡さないので、
        // このスイートは常にツリー表示で回す。
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorExpansionTests"),
            isTreeLayoutAvailable: true
        )
        preference.layoutMode = .tree
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in rootEntries },
            childrenLister: childrenLister,
            resolveGitRoot: { _ in nil }
        )
        let host = SidebarNavigatorStubHost(
            currentFileURL: currentDirectory.appendingPathComponent("fileA.mmd")
        )
        navigator.attach(to: host)
        return (navigator, host)
    }

    /// サイドバー全体で 1 つの世代にすると、後から始まった B の展開が先行する A の
    /// 結果を捨ててしまう。フォルダごとに分けていればどちらの行も残る(AC #1 / #3)。
    @Test("2 つのフォルダを同時に展開しても、互いの列挙結果を破棄しない")
    func concurrentExpansionsKeepBothResults() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorExpansionTests-concurrent")
        let dirA = base.appendingPathComponent("a", isDirectory: true)
        let dirB = base.appendingPathComponent("b", isDirectory: true)
        let rootEntries = [
            FileListEntry(url: dirA, kind: .folder), FileListEntry(url: dirB, kind: .folder),
        ]
        // A の列挙をここで足止めし、B を先に完了させてから開放する。
        let gateA = AsyncGate()
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: rootEntries
        ) { url, _, _ in
            if url.normalizedPathKey == dirA.normalizedPathKey {
                await gateA.wait()
                return [FileListEntry(url: dirA.appendingPathComponent("a1.mmd"), kind: .file)]
            }
            return [FileListEntry(url: dirB.appendingPathComponent("b1.mmd"), kind: .file)]
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value

        navigator.expandFolder(dirA.normalizedPathKey, at: dirA)
        navigator.expandFolder(dirB.normalizedPathKey, at: dirB)
        await Task.yield()
        await gateA.open()
        // 2 つの列挙タスクが着地して行を組み直すまで譲る。
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        let names = navigator.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains("a1.mmd"))
        #expect(names.contains("b1.mmd"))
    }

    /// ルート切り替えは進行中の展開をすべて無効化する。無効化しないと、
    /// 新しいルートの行配列へ前のツリーの子が混ざる(AC #2)。
    @Test("ルート切り替え後に着地した子リストは反映されない")
    func rootSwitchDiscardsInFlightExpansion() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorExpansionTests-root")
        let dirA = base.appendingPathComponent("a", isDirectory: true)
        let other = Self.home.appendingPathComponent(
            "SidebarNavigatorExpansionTests-root-other", isDirectory: true
        )
        let gate = AsyncGate()
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: [FileListEntry(url: dirA, kind: .folder)]
        ) { _, _, _ in
            await gate.wait()
            return [FileListEntry(url: dirA.appendingPathComponent("stale.mmd"), kind: .file)]
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        navigator.expandFolder(dirA.normalizedPathKey, at: dirA)
        await Task.yield()

        navigator.navigateToFolder(other)
        await navigator.pendingListingTask?.value
        await gate.open()
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(navigator.expansion.expandedKeys.isEmpty)
        #expect(!navigator.fileListModel.entries.map(\.url.lastPathComponent).contains("stale.mmd"))
    }

    /// 展開したサブフォルダ内のファイルを選んでいる状態で一覧を取り直すと、
    /// 選択維持の判定がルート直下しか見ていない場合に選択が currentFileURL へ戻る。
    @Test("展開したサブフォルダ内の選択が、一覧の取り直しで失われない")
    func selectionInsideExpandedFolderSurvivesRefresh() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorExpansionTests-selection")
        let dirA = base.appendingPathComponent("a", isDirectory: true)
        let nested = dirA.appendingPathComponent("nested.mmd")
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: [FileListEntry(url: dirA, kind: .folder)]
        ) { _, _, _ in [FileListEntry(url: nested, kind: .file)] }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        navigator.expandFolder(dirA.normalizedPathKey, at: dirA)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        navigator.fileListModel.selection = nested

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(navigator.fileListModel.selection?.normalizedPathKey == nested.normalizedPathKey)
    }

    /// 展開 1 回につき列挙 1 回。行の組み直しや一覧の再反映では列挙し直さない(AC #5)。
    @Test("同じフォルダを 2 回展開しても、子リストの列挙は 1 回しか走らない")
    func expandingTwiceListsChildrenOnce() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorExpansionTests-cost")
        let dirA = base.appendingPathComponent("a", isDirectory: true)
        let counter = CallCounter()
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: [FileListEntry(url: dirA, kind: .folder)]
        ) { _, _, _ in
            await counter.increment()
            return []
        }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        navigator.expandFolder(dirA.normalizedPathKey, at: dirA)
        navigator.expandFolder(dirA.normalizedPathKey, at: dirA)
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(await counter.count == 1)
    }

    /// `SidebarExpansion.material.failed` が `SidebarRowBuilder` まで配線されているか。
    /// 状態と表示のどちらを正しく作っても、この 1 本の配線が抜けると失敗は
    /// 「畳んでいる」ように見え、→ キーも無反応になる(TASK-404)。
    @Test("子リストの列挙に失敗すると、そのフォルダ行が列挙失敗の見た目になる")
    func failedChildListingSurfacesOnRow() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorExpansionTests-failed")
        let dirA = base.appendingPathComponent("a", isDirectory: true)
        let (navigator, host) = makeNavigator(
            currentDirectory: base, rootEntries: [FileListEntry(url: dirA, kind: .folder)]
        ) { _, _, _ in nil }
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        navigator.expandFolder(dirA.normalizedPathKey, at: dirA)
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        let row = navigator.fileListModel.entries.first {
            $0.pathKey == dirA.normalizedPathKey
        }
        #expect(row?.disclosure == .expandedFailed)
        // 失敗しても行は増えない(並べる子が無い)。
        #expect(navigator.fileListModel.entries.allSatisfy { $0.depth == 0 })
    }

    private actor CallCounter {
        private(set) var count = 0
        func increment() {
            count += 1
        }
    }
}
