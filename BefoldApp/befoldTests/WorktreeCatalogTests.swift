@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct WorktreeCatalogTests {
    private func worktree(_ path: String, isMain: Bool = false) -> GitWorktree {
        GitWorktree(root: URL(fileURLWithPath: path), isMain: isMain)
    }

    @Test("refresh で解決した一覧を同期で読み出せる")
    func returnsResolvedWorktreesSynchronouslyAfterRefresh() async {
        let main = URL(fileURLWithPath: "/repos/befold")
        let resolved = [worktree("/repos/befold", isMain: true), worktree("/repos/wt-a")]
        let catalog = WorktreeCatalog(resolver: { _ in resolved })

        await catalog.refresh(mainRoots: [main])

        #expect(catalog.worktrees(forMainRoot: main) == resolved)
    }

    @Test("未解決の本体ルートは空配列を返す")
    func returnsEmptyForUnresolvedMainRoot() async {
        let catalog = WorktreeCatalog(resolver: { root in [GitWorktree(root: root, isMain: true)] })
        await catalog.refresh(mainRoots: [URL(fileURLWithPath: "/repos/befold")])

        #expect(catalog.worktrees(forMainRoot: URL(fileURLWithPath: "/repos/other")).isEmpty)
    }

    @Test("再 refresh でキャッシュが最新の解決結果に差し替わる")
    func replacesCacheOnSubsequentRefresh() async {
        let main = URL(fileURLWithPath: "/repos/befold")
        let counter = ResolveCounter()
        let catalog = WorktreeCatalog(resolver: { root in
            let main = GitWorktree(root: root, isMain: true)
            guard counter.increment() > 1 else { return [main] }
            return [main, GitWorktree(root: root.appendingPathComponent("wt"), isMain: false)]
        })

        await catalog.refresh(mainRoots: [main])
        #expect(catalog.worktrees(forMainRoot: main).count == 1)

        await catalog.refresh(mainRoots: [main])
        #expect(catalog.worktrees(forMainRoot: main).count == 2)
    }

    @Test("解決済みの本体ルートでも refresh のたびに解決し直す")
    func resolvesAgainOnEveryRefresh() async {
        // アプリ起動中に worktree が追加/削除されても追随できるよう、キャッシュ済みでも呼び直す。
        let main = URL(fileURLWithPath: "/repos/befold")
        let counter = ResolveCounter()
        let catalog = WorktreeCatalog(resolver: { root in
            _ = counter.increment()
            return [GitWorktree(root: root, isMain: true)]
        })

        await catalog.refresh(mainRoots: [main])
        await catalog.refresh(mainRoots: [main])

        #expect(counter.value == 2)
    }
}

/// resolver の呼び出し回数を MainActor 外からも数えるためのカウンタ。
private final class ResolveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
