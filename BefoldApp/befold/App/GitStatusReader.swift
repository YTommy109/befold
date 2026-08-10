import BefoldKit
import Foundation
import libgit2

/// 1 リポジトリルート分の git 状態。
struct GitStatusSnapshot: Equatable, Sendable {
    /// ファイルの正規化済み絶対パス(`URL.normalizedPathKey`)→ 状態。
    ///
    /// キーを URL ではなく正規化パス文字列にするのは、リポジトリ全体の規約
    /// (`PathKeyedDictionary` / `WorktreeCatalog` / `FileListEntry.pathKey`)に合わせるため。
    /// URL のままだとシンボリックリンク経由の別表記で `FileListEntry` と突合できない。
    /// 相対パスではなく絶対パスに解決済みにしてあるのは、`resolvingSymlinksInPath()` が
    /// ファイルシステムに触るため。取得を担うこの型はメインアクター外で動くので、
    /// 変換をここで済ませてメインスレッドでの stat を避ける。
    var statuses: [String: GitFileStatus]
    /// 親リポジトリの `git status` では配下を答えられない境界(サブモジュール・
    /// ネストしたリポジトリ)のルート。キーは `statuses` と同じ正規化済み絶対パス。
    ///
    /// **この集合が空であることは「境界が無い」ではなく「境界を見つけられなかった」も
    /// 含む**(下記の限界を参照)。配下を縮退させる用途にだけ使い、
    /// 「ここは普通のディレクトリだ」という結論には使わない。
    var indeterminateRoots: Set<String> = []
    /// 取得時点の `.git/index` の最終更新日時。index を動かす操作(add / commit / checkout)の
    /// 検出とキャッシュの妥当性判定に使う。**素の作業ツリー編集では変化しない**ため、
    /// 編集への追従をこの値に頼ってはならない。
    var indexFingerprint: Date?
    /// 監視対象にする `.git/index` の実パス。worktree では `.git` がファイルで実 gitdir を
    /// 指すため、呼び出し側が自力で組み立てられない。取得できなければ nil。
    var indexURL: URL?

    static let empty = GitStatusSnapshot()

    init(
        statuses: [String: GitFileStatus] = [:],
        indeterminateRoots: Set<String> = [],
        indexFingerprint: Date? = nil,
        indexURL: URL? = nil
    ) {
        self.statuses = statuses
        self.indeterminateRoots = indeterminateRoots
        self.indexFingerprint = indexFingerprint
        self.indexURL = indexURL
    }
}

/// リポジトリルート単位で git の状態を取得する。
///
/// 実装はファイルシステムを走査するため、必ずメインアクターの外で呼ぶこと。
protocol GitStatusReading: Sendable {
    /// root 配下の変更ファイルを状態付きで返す。
    /// - Returns: 取得できたスナップショット。リポジトリを開けなかった場合は nil。
    ///   「動いた結果、変更が無い/リポジトリではない」は空のスナップショットで返る。
    ///   呼び出し側はこの区別でキャッシュの可否を決める(nil はキャッシュしてはならない)。
    func status(forRepositoryAt root: URL) -> GitStatusSnapshot?
    /// `.git/index` の最終更新日時。git を起動せずファイル stat だけで得られるため、
    /// 「index が動いたときだけ status を取り直す」判定に使う。
    func indexFingerprint(forRepositoryAt root: URL) -> Date?
}

/// libgit2 の status API で状態を読む本番実装。
struct GitStatusReader: GitStatusReading {
    private let repository: any GitRepositoryReading
    private let comparisonBase: any GitComparisonBaseResolving
    private let fileReader: any FileReading

    init(
        repository: any GitRepositoryReading = GitRepository(),
        comparisonBase: any GitComparisonBaseResolving = GitComparisonBaseResolver(),
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.repository = repository
        self.comparisonBase = comparisonBase
        self.fileReader = fileReader
    }

    func indexFingerprint(forRepositoryAt root: URL) -> Date? {
        repository.indexFingerprint(at: root)
    }

    /// status・サブモジュール列挙・ブランチ差分を **1 回のリポジトリオープンの中で**まとめて行う。
    ///
    /// この経路はサイドバーの `.git/index` 監視コールバックごとに走る最頻経路であり、
    /// 3 つを別々に開くと 1 回の更新でオープンが 3 倍になる。ヘルパーが URL ではなく
    /// 開いたリポジトリを受け取る形にしてあるのは、開き直す実装を書けなくするため。
    func status(forRepositoryAt root: URL) -> GitStatusSnapshot? {
        let outcome = GitLibrary.withRepository(at: root) { repository -> GitStatusSnapshot in
            var statuses: [String: GitFileStatus] = [:]
            var boundaries = Set<String>()
            collectWorkingTree(in: repository, root: root, statuses: &statuses, boundaries: &boundaries)
            for path in Self.registeredSubmodulePaths(in: repository) {
                boundaries.insert(root.appendingPathComponent(path).normalizedPathKey)
            }
            // base ブランチからのコミット済み変更。検出できない場合(デフォルトブランチが
            // 分からない・履歴が繋がっていない)はブランチ内変更だけを諦め、
            // staged / unstaged / untracked の表示は続ける。
            let base = comparisonBase.comparisonBase(forRepositoryAt: root)
            for (relativePath, change) in Self.branchChanges(in: repository, base: base) {
                let key = root.appendingPathComponent(relativePath).normalizedPathKey
                statuses[key, default: GitFileStatus()].branchChange = change
            }
            return GitStatusSnapshot(
                statuses: statuses,
                indeterminateRoots: boundaries,
                indexFingerprint: self.repository.indexFingerprint(at: root),
                indexURL: self.repository.indexURL(at: root)
            )
        }
        switch outcome {
        case let .success(snapshot):
            return snapshot
        case .failure(.notARepository):
            // 答えとして確定しているのでキャッシュしてよい。
            return .empty
        case .failure(.unusable):
            return nil
        }
    }

    // MARK: - Working Tree

    /// status に渡すフラグ。**設定していないもの**にこそ理由がある。
    ///
    /// - `GIT_STATUS_OPT_UPDATE_INDEX`: status が `.git/index` を書き換える。fingerprint による
    ///   キャッシュ無効化と組み合わさると「status 実行 → fingerprint 変化 → 監視発火 → status」の
    ///   自己励振ループになる(外部 git 方式の `--no-optional-locks` が防いでいたもの)。
    ///   `GitStatusReaderIntegrationTests.statusDoesNotDisturbIndexFingerprint` が守る。
    /// - `GIT_STATUS_OPT_EXCLUDE_SUBMODULES`: 設定するとサブモジュールのエントリが 1 件も出ず、
    ///   中身が変更されたサブモジュールにバッジが付かなくなる(実測。外部 git 方式では
    ///   porcelain が `1 .M S.MU sub` を出しており、バッジが付いていた)。
    ///   `GitStatusReaderIntegrationTests.showsBadgeForDirtySubmodule` が守る。
    /// - `GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS`: 設定しないことで、丸ごと新しいディレクトリが
    ///   末尾スラッシュ付きの 1 エントリに畳まれる。ネストしたリポジトリの検出は
    ///   この畳み込みが前提。
    /// - `GIT_STATUS_OPT_INCLUDE_IGNORED` / `..._INCLUDE_UNREADABLE`: ignored と読めないファイルは
    ///   バッジの対象外。外部 git 方式と同じく黙って無視する。
    private static let statusFlags: UInt32 =
        GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue
            | GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX.rawValue
            | GIT_STATUS_OPT_RENAMES_INDEX_TO_WORKDIR.rawValue

    /// 作業ツリーの状態を集め、同時にネストしたリポジトリの境界も拾う。
    ///
    /// サブモジュールの境界はここでは拾わない。`git_submodule_foreach` が
    /// `.gitmodules` 登録の有無によらず index の gitlink まで列挙するため
    /// (実測。登録を `.gitmodules` と `.git/config` の両方から消しても検出できる)、
    /// エントリのファイルモードを見る判定を重ねても同じ集合にしかならない。
    private func collectWorkingTree(
        in repository: OpaquePointer,
        root: URL,
        statuses: inout [String: GitFileStatus],
        boundaries: inout Set<String>
    ) {
        var options = git_status_options()
        guard git_status_options_init(&options, UInt32(GIT_STATUS_OPTIONS_VERSION)) == 0 else { return }
        options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        options.flags = Self.statusFlags
        var list: OpaquePointer?
        guard git_status_list_new(&list, repository, &options) == 0, let list else { return }
        defer { git_status_list_free(list) }
        for position in 0 ..< git_status_list_entrycount(list) {
            guard let entry = git_status_byindex(list, position)?.pointee,
                  let relativePath = Self.path(of: entry)
            else { continue }
            let url = root.appendingPathComponent(relativePath)
            guard let status = Self.fileStatus(of: entry) else { continue }
            statuses[url.normalizedPathKey] = status
            // 畳まれた未追跡ディレクトリのうち `.git` を持つもの = ネストしたリポジトリ。
            // 親から見れば未追跡ディレクトリ 1 件で、配下は列挙すらされない。
            guard status.isUntracked, relativePath.hasSuffix("/"),
                  fileReader.fileExists(at: url.appendingPathComponent(".git"))
            else { continue }
            boundaries.insert(url.normalizedPathKey)
        }
    }

    /// エントリのルート相対パス。改名では変更後のパス(表示対象は変更後だけ)。
    private static func path(of entry: git_status_entry) -> String? {
        let raw = entry.index_to_workdir?.pointee.new_file.path ?? entry.head_to_index?.pointee.new_file.path
        guard let raw else { return nil }
        let path = String(cString: raw)
        return path.isEmpty ? nil : path
    }

    /// エントリを表示用の状態へ写す。バッジを出す理由が無ければ nil。
    private static func fileStatus(of entry: git_status_entry) -> GitFileStatus? {
        if entry.index_to_workdir?.pointee.status == GIT_DELTA_UNTRACKED {
            return GitFileStatus(indexChange: nil, worktreeChange: nil, isUntracked: true)
        }
        let status = GitFileStatus(
            indexChange: entry.head_to_index.flatMap { GitFileStatus.Change(delta: $0.pointee.status) },
            worktreeChange: entry.index_to_workdir.flatMap { GitFileStatus.Change(delta: $0.pointee.status) }
        )
        return status.isClean ? nil : status
    }

    // MARK: - Boundaries

    /// サブモジュールのルート相対パス。
    ///
    /// `.gitmodules` の登録だけでなく index の gitlink も列挙するため、登録が消えた
    /// サブモジュールもここで拾える(実測)。clean なサブモジュールは status に
    /// 1 件も出ないので、いずれにせよ境界の検出はここが唯一の出所になる。
    /// コールバックが受け取る名前ではなく `git_submodule_path` を使う
    /// (`.gitmodules` の `[submodule "<名前>"]` は path と一致しないことがある)。
    private static func registeredSubmodulePaths(in repository: OpaquePointer) -> [String] {
        var paths: [String] = []
        withUnsafeMutablePointer(to: &paths) { payload in
            _ = git_submodule_foreach(repository, { submodule, _, payload in
                guard let submodule, let payload, let path = git_submodule_path(submodule) else { return 0 }
                payload.assumingMemoryBound(to: [String].self).pointee.append(String(cString: path))
                return 0
            }, payload)
        }
        return paths
    }

    // MARK: - Branch Diff

    /// 現在のブランチが base から変更したコミット済みファイル(ルート相対パス → 変更種別)。
    /// base を特定できない場合は空を返す(この機能だけを諦める)。
    /// 基準の解決は `GitComparisonBaseResolving` に集約してある。差分ビューアと
    /// 同じ起点を使うことが、バッジと差分の食い違いを防ぐ唯一の担保(TASK-352)。
    private static func branchChanges(
        in repository: OpaquePointer, base: String?
    ) -> [String: GitFileStatus.Change] {
        guard let base,
              let baseTree = tree(in: repository, revision: base),
              let headTree = tree(in: repository, revision: "HEAD")
        else { return [:] }
        defer { git_object_free(baseTree); git_object_free(headTree) }
        var diff: OpaquePointer?
        guard git_diff_tree_to_tree(&diff, repository, baseTree, headTree, nil) == 0, let diff else { return [:] }
        defer { git_diff_free(diff) }
        // 改名を検出する。既定のオプションは `git diff` と同じく改名のみで、複製は拾わない
        // (`git diff --name-status` が C を出すのは -C を付けたときだけ)。
        var findOptions = git_diff_find_options()
        if git_diff_find_options_init(&findOptions, UInt32(GIT_DIFF_FIND_OPTIONS_VERSION)) == 0 {
            _ = git_diff_find_similar(diff, &findOptions)
        }
        var changes: [String: GitFileStatus.Change] = [:]
        for position in 0 ..< git_diff_num_deltas(diff) {
            guard let delta = git_diff_get_delta(diff, position)?.pointee,
                  let rawPath = delta.new_file.path
            else { continue }
            // 解釈できない種別でもエントリは捨てない。捨てると「変更あり」が
            // 「変更なし」と同じ無表示に縮退するため、種別だけを諦める。
            changes[String(cString: rawPath)] = GitFileStatus.Change(delta: delta.status) ?? .modified
        }
        return changes
    }

    /// リビジョン指定(コミット ID・`HEAD`)を tree へ解決する。呼び出し側が `git_object_free` する。
    private static func tree(in repository: OpaquePointer, revision: String) -> OpaquePointer? {
        var object: OpaquePointer?
        guard git_revparse_single(&object, repository, revision) == 0, let object else { return nil }
        defer { git_object_free(object) }
        var tree: OpaquePointer?
        guard git_object_peel(&tree, object, GIT_OBJECT_TREE) == 0 else { return nil }
        return tree
    }
}
