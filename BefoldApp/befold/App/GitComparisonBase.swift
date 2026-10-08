import Foundation
import libgit2

/// 「何と比べた変更か」の起点を決める。
///
/// サイドバーのバッジ(`GitStatusReader`)と差分ビューア(`GitDiffReader`)は同じ問いに
/// 答える機能であり、**基準がずれると「バッジは変更ありなのに差分は空」になる**。
/// この食い違いは 2 度起きている。1 度目は差分側が index と比べており、ステージ済みの
/// 変更が差分から消えた(`GitDiffReader` のコメント参照)。2 度目はブランチでコミット済みの
/// ファイルで、バッジは merge-base 基準で変更ありと出す一方、差分側は HEAD 基準で空を
/// 返していた(TASK-352)。個別に直すのをやめ、基準の解決をここ 1 箇所へ集約する。
///
/// 実装はファイルシステムを走査するため、必ずメインアクターの外で呼ぶこと。
protocol GitComparisonBaseResolving: Sendable {
    /// - Returns: 比較の起点。特定できなければ nil。
    ///   nil は「分からない」であって「HEAD と同じ」ではない。縮退のしかたは
    ///   呼び出し側が決める(バッジはブランチ差分を諦め、差分ビューアは HEAD へ落とす)。
    func comparisonBase(forRepositoryAt root: URL, target: GitComparisonTarget) -> GitComparisonResolution?
}

/// 何を起点に比べるか。窓ごとの選択肢(TASK-353)に対応する。
enum GitComparisonTarget: Sendable, Hashable, CaseIterable {
    /// このブランチの変更。`merge-base(HEAD, 親ブランチ)`。親が分からなければデフォルトブランチへ縮退する。
    case parentBranch
    /// スタック全体の変更。`merge-base(HEAD, デフォルトブランチ)`(従来の挙動)。
    case defaultBranch
    /// 作業中の変更。`HEAD` そのもの。
    case head

    /// 新しい窓の出発点。基準は窓ごとのライブ値で永続化しない(TASK-353)。
    static let windowDefault = GitComparisonTarget.parentBranch
}

/// 起点の解決結果。メニューやラベルはこの値を読む(開く瞬間に main で再解決しない)。
struct GitComparisonResolution: Sendable, Equatable {
    /// 起点コミットの 16 進表記。`git_revparse_single` に渡せる。
    let baseID: String
    /// 表示用の基準ブランチ名。`.head` では nil。縮退したときはデフォルトブランチ名。
    let baseBranch: String?
    /// 親ブランチが分かっていて、デフォルトブランチと異なる(=「スタック全体」を出す意味がある)。
    /// どの target で解決しても同じ値になる。
    let parentDiffersFromDefault: Bool
    /// `.parentBranch` を求められたが親が分からず、デフォルトブランチへ落とした。
    let degraded: Bool
}

/// デフォルトブランチ / 親ブランチとの merge-base を起点にする本番実装。
///
/// ブランチで作業している間は「このブランチが base から変えたもの」全体が対象になり、
/// コミット済みの変更も差分に出る。main の上ではデフォルトブランチとの merge-base が
/// HEAD 自身になるため、結果として「未コミットの変更」を見るのと同じになる。
struct GitComparisonBaseResolver: GitComparisonBaseResolving {
    /// merge-base はコミット・チェックアウトのたびに動くため**キャッシュしない**。
    /// 保持すると、コミット直後に「さっきまでの base」で比べ続けることになり、
    /// `GitStatusStore` が fingerprint で無効化しているのと同じ陳腐化を持ち込む。
    func comparisonBase(forRepositoryAt root: URL, target: GitComparisonTarget) -> GitComparisonResolution? {
        let outcome = GitLibrary.withRepository(at: root) { repository -> GitComparisonResolution? in
            guard let defaultBranch = Self.defaultBranch(in: repository) else { return nil }
            let parent = GitParentBranchResolver.parentBranch(in: repository).flatMap {
                Self.usableRef(for: $0, in: repository)
            }
            let differs = parent.map { $0.name != Self.localName(of: defaultBranch) } ?? false
            func resolution(base: String, branch: String?, degraded: Bool = false) -> GitComparisonResolution {
                GitComparisonResolution(
                    baseID: base, baseBranch: branch, parentDiffersFromDefault: differs, degraded: degraded
                )
            }
            switch target {
            case .head:
                let headOID = Self.commitID(in: repository, revision: "HEAD")
                guard let headOID, let head = Self.hexString(of: headOID) else { return nil }
                return resolution(base: head, branch: nil)
            case .parentBranch:
                if let parent, let base = Self.mergeBase(in: repository, with: parent.ref) {
                    return resolution(base: base, branch: parent.name)
                }
                fallthrough
            case .defaultBranch:
                guard let base = Self.mergeBase(in: repository, with: defaultBranch) else { return nil }
                return resolution(base: base, branch: defaultBranch, degraded: target == .parentBranch)
            }
        }
        return (try? outcome.get()) ?? nil
    }

    /// 親ブランチ名を revparse できる ref へ解く。ローカルに無くてもリモートに残っていれば使う。
    private static func usableRef(for name: String, in repository: OpaquePointer) -> (name: String, ref: String)? {
        for ref in ["refs/heads/\(name)", "refs/remotes/origin/\(name)"] {
            var reference: OpaquePointer?
            guard git_reference_lookup(&reference, repository, ref) == 0 else { continue }
            git_reference_free(reference)
            return (name, ref)
        }
        return nil
    }

    /// `origin/main` → `main`。親ブランチ名との比較用。
    private static func localName(of branch: String) -> String {
        branch.hasPrefix("origin/") ? String(branch.dropFirst("origin/".count)) : branch
    }

    /// HEAD と `revision` の merge-base の 16 進表記。
    private static func mergeBase(in repository: OpaquePointer, with revision: String) -> String? {
        guard var headID = commitID(in: repository, revision: "HEAD"),
              var otherID = commitID(in: repository, revision: revision)
        else { return nil }
        var base = git_oid()
        guard git_merge_base(&base, repository, &headID, &otherID) == 0 else { return nil }
        return hexString(of: base)
    }

    /// リビジョン指定をコミット ID へ解決する。
    private static func commitID(in repository: OpaquePointer, revision: String) -> git_oid? {
        var object: OpaquePointer?
        guard git_revparse_single(&object, repository, revision) == 0, let object else { return nil }
        defer { git_object_free(object) }
        var peeled: OpaquePointer?
        // 注釈付きタグ経由でも辿れるようコミットまで peel する。
        guard git_object_peel(&peeled, object, GIT_OBJECT_COMMIT) == 0, let peeled else { return nil }
        defer { git_object_free(peeled) }
        return git_object_id(peeled)?.pointee
    }

    private static func hexString(of oid: git_oid) -> String? {
        var oid = oid
        var buffer = [CChar](repeating: 0, count: Int(GIT_OID_SHA1_HEXSIZE) + 1)
        let text = buffer.withUnsafeMutableBufferPointer { pointer -> String? in
            guard let base = pointer.baseAddress, git_oid_tostr(base, pointer.count, &oid) != nil else {
                return nil
            }
            return String(cString: base)
        }
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// base として使うデフォルトブランチ名。
    ///
    /// まず `origin/HEAD` の指す先(クローン時に決まる本来のデフォルト)を見る。
    /// 無い場合(origin 無し・`--single-branch` クローンなど)はローカルの慣例名を試す。
    /// どれも無ければ nil = 「base が分からない」。この順序は外部 git 方式と同じ。
    private static func defaultBranch(in repository: OpaquePointer) -> String? {
        if let name = originHeadBranch(in: repository) { return name }
        return ["main", "master"].first { localBranchExists(named: $0, in: repository) }
    }

    private static func localBranchExists(named name: String, in repository: OpaquePointer) -> Bool {
        var reference: OpaquePointer?
        guard git_branch_lookup(&reference, repository, name, GIT_BRANCH_LOCAL) == 0 else { return false }
        git_reference_free(reference)
        return true
    }

    /// `origin/HEAD` が指すブランチ名(例: `origin/main`)。解決できなければ nil。
    ///
    /// `refs/remotes/origin/HEAD` はシンボリック参照で、その target は
    /// `refs/remotes/origin/main` のような完全名。外部 git 方式の `symbolic-ref --short` と
    /// 同じ短縮形にするため `refs/remotes/` を落とす。
    private static func originHeadBranch(in repository: OpaquePointer) -> String? {
        var reference: OpaquePointer?
        guard git_reference_lookup(&reference, repository, "refs/remotes/origin/HEAD") == 0,
              let reference
        else { return nil }
        defer { git_reference_free(reference) }
        guard let target = git_reference_symbolic_target(reference) else { return nil }
        let name = String(cString: target)
        let prefix = "refs/remotes/"
        guard name.hasPrefix(prefix) else { return name.isEmpty ? nil : name }
        let shortened = String(name.dropFirst(prefix.count))
        return shortened.isEmpty ? nil : shortened
    }
}
