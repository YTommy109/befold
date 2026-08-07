import Foundation

/// 「何と比べた変更か」の起点を決める。
///
/// サイドバーのバッジ(`GitStatusReader`)と差分ビューア(`GitDiffReader`)は同じ問いに
/// 答える機能であり、**基準がずれると「バッジは変更ありなのに差分は空」になる**。
/// この食い違いは 2 度起きている。1 度目は差分側が index と比べており、ステージ済みの
/// 変更が差分から消えた(`GitDiffReader` のコメント参照)。2 度目はブランチでコミット済みの
/// ファイルで、バッジは merge-base 基準で変更ありと出す一方、差分側は HEAD 基準で空を
/// 返していた(TASK-352)。個別に直すのをやめ、基準の解決をここ 1 箇所へ集約する。
///
/// 実装は subprocess を起こすため、必ずメインアクターの外で呼ぶこと。
protocol GitComparisonBaseResolving: Sendable {
    /// - Returns: 比較の起点にするコミット。特定できなければ nil。
    ///   nil は「分からない」であって「HEAD と同じ」ではない。縮退のしかたは
    ///   呼び出し側が決める(バッジはブランチ差分を諦め、差分ビューアは HEAD へ落とす)。
    func comparisonBase(forRepositoryAt root: URL) -> String?
}

/// `git merge-base HEAD <defaultBranch>` を起点にする本番実装。
///
/// ブランチで作業している間は「このブランチが base から変えたもの」全体が対象になり、
/// コミット済みの変更も差分に出る。main の上ではデフォルトブランチとの merge-base が
/// HEAD 自身になるため、結果として「未コミットの変更」を見るのと同じになる。
struct GitComparisonBaseResolver: GitComparisonBaseResolving {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    /// merge-base はコミット・チェックアウトのたびに動くため**キャッシュしない**。
    /// 保持すると、コミット直後に「さっきまでの base」で比べ続けることになり、
    /// `GitStatusStore` が fingerprint で無効化しているのと同じ陳腐化を持ち込む。
    func comparisonBase(forRepositoryAt root: URL) -> String? {
        guard let defaultBranch = defaultBranch(forRepositoryAt: root),
              case let .output(data) = runner.run(["merge-base", "HEAD", defaultBranch], in: root),
              let base = String(bytes: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !base.isEmpty
        else { return nil }
        return base
    }

    /// base として使うデフォルトブランチ名。
    ///
    /// まず `origin/HEAD` の指す先(クローン時に決まる本来のデフォルト)を見る。
    /// 無い場合(origin 無し・`--single-branch` クローンなど)はローカルの慣例名を試す。
    /// どれも無ければ nil = 「base が分からない」。
    private func defaultBranch(forRepositoryAt root: URL) -> String? {
        if let name = originHeadBranch(forRepositoryAt: root) { return name }
        return ["main", "master"].first { name in
            if case .output = runner.run(["rev-parse", "--verify", "--quiet", name], in: root) {
                return true
            }
            return false
        }
    }

    /// `origin/HEAD` が指すブランチ名(例: `origin/main`)。解決できなければ nil。
    private func originHeadBranch(forRepositoryAt root: URL) -> String? {
        guard case let .output(data) = runner.run(
            ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: root
        ),
            let name = String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return nil }
        return name
    }
}
