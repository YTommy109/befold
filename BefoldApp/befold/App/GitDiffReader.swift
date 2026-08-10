import Foundation
import libgit2

/// 表示中のファイル 1 つ分の差分を取得する。
///
/// 実装はファイルシステムを走査するため、必ずメインアクターの外で呼ぶこと
/// (`GitStatusReading` と同じ契約)。
protocol GitDiffReading: Sendable {
    /// - Returns: 取得できた結果。リポジトリを開けなかった場合は nil。
    ///   nil は「不明」であって「差分なし」ではないため、呼び出し側はキャッシュしてはならない。
    func diff(forFileAt url: URL, in root: URL) -> GitFileDiff?
}

/// 比較の起点から作業ツリーまでの unified diff を libgit2 で読む本番実装。
/// 起点の決め方は `GitComparisonBaseResolving` が持つ(サイドバーのバッジと同じもの)。
struct GitDiffReader: GitDiffReading {
    /// 描画に載せる差分の上限バイト数。
    ///
    /// 差分取得は保存のたびに走りうるため、生成ファイルの全書き換えのような巨大な diff を
    /// そのまま WebView へ送るとメインスレッドが張り付く。上限は表示側の判断材料として返す。
    static let maxDiffBytes = 1 << 20

    /// 文脈行数。ファイル全体が 1 つのハンクに収まる十分な大きさにする
    /// (変更の周辺だけを抜き出すと、ビューアとして前後が読めなくなるため)。
    /// これより行数の多いファイルは上限バイト数で先に弾かれる。
    static let wholeFileContextLines: UInt32 = 1_000_000

    private let comparisonBase: any GitComparisonBaseResolving

    init(comparisonBase: any GitComparisonBaseResolving = GitComparisonBaseResolver()) {
        self.comparisonBase = comparisonBase
    }

    func diff(forFileAt url: URL, in root: URL) -> GitFileDiff? {
        // 比較の起点はサイドバーのバッジと同じものを使う。ここを独自に決めると
        // 「バッジは変更ありなのに差分は空」が生まれる。過去 2 度それが起きている
        // (index 比較でステージ済みが消えた件と、HEAD 比較でブランチのコミット済み
        // 変更が消えた TASK-352)。
        //
        // 起点が分からないとき(デフォルトブランチを特定できない・リモートが無い・
        // detached HEAD)だけ HEAD へ落とす。差分が空だったから落とす、ではない。
        let base = comparisonBase.comparisonBase(forRepositoryAt: root) ?? "HEAD"
        let outcome = GitLibrary.withRepository(at: root) { repository -> GitFileDiff in
            // コミットが 1 つも無いリポジトリでは比較の相手が存在しない。
            // 出力の有無からは区別できないため、HEAD が未生成かという事実で判定する。
            guard git_repository_head_unborn(repository) == 0 else { return .noCommits }
            guard let relativePath = Self.relativePath(of: url, in: root) else { return .notInRepository }
            return Self.diff(in: repository, relativePath: relativePath, base: base)
        }
        switch outcome {
        case let .success(diff):
            return diff
        case .failure(.notARepository):
            return .notInRepository
        case .failure(.unusable):
            return nil
        }
    }

    /// base の tree と作業ツリー(index を織り込んだもの)の差分。
    /// `git diff <base> -- <path>` と同じ比較。
    ///
    /// **`GIT_DIFF_UPDATE_INDEX` を設定しない**のが要点。設定すると差分の取得が
    /// `.git/index` の stat キャッシュを書き戻し、fingerprint を見ている監視側と
    /// 「差分取得 → index 変化 → 監視発火 → 差分取得」の自己励振ループになる
    /// (外部 git 方式の `--no-optional-locks` が防いでいたもの)。
    /// `GitDiffReaderIntegrationTests.diffDoesNotDisturbIndexFingerprint` が守る。
    ///
    /// 文脈行は全文を含む大きさにする。ビューアは「ファイルを読む」ための画面で、
    /// 変更の周辺だけを抜き出すと前後が飛んで読めなくなる。全文を 1 つのハンクに
    /// 収めることで、通常のソース表示と同じ見え方のまま変更行に印が付く
    /// (結果としてハンクの区切りも出なくなる)。
    ///
    /// pathspec の組み立てと差分の生成を同じスコープに閉じてあるのは、
    /// `git_strarray` が指す配列が `git_diff_tree_to_workdir_with_index` の呼び出しより
    /// 長生きしなければならないため(オプションを作って返す形にすると領域が先に消える)。
    private static func diff(
        in repository: OpaquePointer, relativePath: String, base: String
    ) -> GitFileDiff {
        guard let baseTree = tree(in: repository, revision: base) else { return .noCommits }
        defer { git_object_free(baseTree) }
        return relativePath.withCString { rawPath -> GitFileDiff in
            var pathspec: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: rawPath)]
            return pathspec.withUnsafeMutableBufferPointer { buffer -> GitFileDiff in
                var options = git_diff_options()
                guard git_diff_options_init(&options, UInt32(GIT_DIFF_OPTIONS_VERSION)) == 0 else {
                    return .noChanges
                }
                options.context_lines = wholeFileContextLines
                options.pathspec = git_strarray(strings: buffer.baseAddress, count: buffer.count)
                var diff: OpaquePointer?
                guard git_diff_tree_to_workdir_with_index(&diff, repository, baseTree, &options) == 0,
                      let diff
                else { return .noChanges }
                defer { git_diff_free(diff) }
                return result(of: diff, in: repository, relativePath: relativePath)
            }
        }
    }

    /// 差分を表示用の結果へ写す。
    private static func result(
        of diff: OpaquePointer, in repository: OpaquePointer, relativePath: String
    ) -> GitFileDiff {
        // 出力が空でも「変更なし」とは限らない。未追跡ファイルは base に対応物が無く、
        // 差分は成功して空を返す。空かどうかではなく追跡されているかで判定する。
        guard git_diff_num_deltas(diff) > 0 else {
            return isTracked(relativePath, in: repository) ? .noChanges : .untracked
        }
        var buffer = git_buf()
        defer { git_buf_dispose(&buffer) }
        guard git_diff_to_buf(&buffer, diff, GIT_DIFF_FORMAT_PATCH) == 0, let pointer = buffer.ptr else {
            return .noChanges
        }
        // バイナリ判定は git の固定英文(`Binary files … differ`)の行頭一致ではなく、
        // libgit2 が delta に付ける属性で行う。文言は版やロケールで変わりうるうえ、
        // その文字列を含むテキストファイルを誤ってバイナリ扱いにしてしまう。
        //
        // 判定を patch の生成**後**に置くのが要点。`GIT_DIFF_FLAG_BINARY` は中身を
        // 読んで初めて確定するため、生成前の delta には立っていない(実測)。
        if isBinary(diff) { return .binary }
        let data = Data(bytes: pointer, count: buffer.size)
        if data.count > maxDiffBytes { return .tooLarge(byteCount: data.count) }
        guard let text = String(data: data, encoding: .utf8) else { return .binary }
        return text.isEmpty ? .noChanges : .diff(text)
    }

    /// いずれかの delta がバイナリなら true。pathspec で 1 ファイルに絞ってあるため
    /// 実際には 0 件か 1 件しかない。
    private static func isBinary(_ diff: OpaquePointer) -> Bool {
        (0 ..< git_diff_num_deltas(diff)).contains { position in
            guard let delta = git_diff_get_delta(diff, position)?.pointee else { return false }
            return delta.flags & GIT_DIFF_FLAG_BINARY.rawValue != 0
        }
    }

    /// index に載っていれば追跡されている。
    private static func isTracked(_ relativePath: String, in repository: OpaquePointer) -> Bool {
        var index: OpaquePointer?
        guard git_repository_index(&index, repository) == 0, let index else { return false }
        defer { git_index_free(index) }
        return git_index_get_bypath(index, relativePath, 0) != nil
    }

    /// リビジョン指定を tree へ解決する。呼び出し側が `git_object_free` する。
    private static func tree(in repository: OpaquePointer, revision: String) -> OpaquePointer? {
        var object: OpaquePointer?
        guard git_revparse_single(&object, repository, revision) == 0, let object else { return nil }
        defer { git_object_free(object) }
        var tree: OpaquePointer?
        guard git_object_peel(&tree, object, GIT_OBJECT_TREE) == 0 else { return nil }
        return tree
    }

    /// リポジトリルートからの相対パス。ルート配下でなければ nil。
    ///
    /// libgit2 の pathspec はリポジトリ相対でなければ一致しない
    /// (外部 git 方式は絶対パスをそのまま渡していた)。
    private static func relativePath(of url: URL, in root: URL) -> String? {
        let filePath = url.resolvingSymlinksInPath().path
        var rootPath = root.resolvingSymlinksInPath().path
        if !rootPath.hasSuffix("/") { rootPath += "/" }
        guard filePath.hasPrefix(rootPath) else { return nil }
        let relative = String(filePath.dropFirst(rootPath.count))
        return relative.isEmpty ? nil : relative
    }
}
