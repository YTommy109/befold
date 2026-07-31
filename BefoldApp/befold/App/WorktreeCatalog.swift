import BefoldKit
import Foundation

/// 本体リポジトリのルートごとの worktree 一覧キャッシュ。
///
/// メニュー表示直前(menuNeedsUpdate)に `git worktree list` を同期実行すると、
/// subprocess の待ちがそのまま UI の固まりになる(RecentRepositoriesMenuController が
/// パス毎のアイコン取得を避けているのと同じ理由)。そこで git 呼び出しは
/// `refresh(mainRoots:)` の非同期側でまとめて行ってここへ載せ、メニュー構築は
/// キャッシュを同期で読むだけにする。
/// まだ解決できていない本体ルートは空配列を返し、呼び出し側が従来どおりの
/// フラット表示へ縮退できるようにする。
@MainActor
final class WorktreeCatalog {
    /// 本体ルートの normalizedPathKey → その worktree 一覧。
    private var cache: [String: [GitWorktree]] = [:]
    /// git を実行して worktree 一覧を得る。MainActor の外で呼ぶため @Sendable。
    private let resolver: @Sendable (URL) -> [GitWorktree]

    init(resolver: @escaping @Sendable (URL) -> [GitWorktree] = { GitRepository().worktrees(forRoot: $0) }) {
        self.resolver = resolver
    }

    /// キャッシュ済みの worktree 一覧を同期で返す。未解決なら空配列。
    func worktrees(forMainRoot root: URL) -> [GitWorktree] {
        cache[root.normalizedPathKey] ?? []
    }

    /// 指定した本体ルート群の worktree 一覧を解決し、キャッシュを差し替える。
    /// 既に載っているルートも解決し直す(アプリ起動中に worktree が追加/削除されても追随するため)。
    /// git の subprocess 待ちが MainActor を止めないよう、解決は detached タスクで行う
    /// (RecentRepositoriesStore.pruneMissingAsync と同じ方針)。
    func refresh(mainRoots: [URL]) async {
        guard !mainRoots.isEmpty else { return }
        let resolver = resolver
        let resolved = await Task.detached(priority: .utility) {
            var result: [String: [GitWorktree]] = [:]
            for root in mainRoots {
                result[root.normalizedPathKey] = resolver(root)
            }
            return result
        }.value
        for (key, worktrees) in resolved {
            cache[key] = worktrees
        }
    }
}
