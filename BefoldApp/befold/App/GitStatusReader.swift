import BefoldKit
import Foundation

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
/// 実装は subprocess を起こすため、必ずメインアクターの外で呼ぶこと。
protocol GitStatusReading: Sendable {
    /// root 配下の変更ファイルを状態付きで返す。
    /// - Returns: 取得できたスナップショット。git を動かせなかった(`.unavailable`)場合は nil。
    ///   「動いた結果、変更が無い/リポジトリではない」は空のスナップショットで返る。
    ///   呼び出し側はこの区別でキャッシュの可否を決める(nil はキャッシュしてはならない)。
    func status(forRepositoryAt root: URL) -> GitStatusSnapshot?
    /// `.git/index` の最終更新日時。git を起動せずファイル stat だけで得られるため、
    /// 「index が動いたときだけ status を取り直す」判定に使う。
    func indexFingerprint(forRepositoryAt root: URL) -> Date?
}

/// `git status --porcelain=v2` で状態を読む本番実装。
struct GitStatusReader: GitStatusReading {
    private let runner: GitCommandRunner
    private let repository: any GitRepositoryReading
    private let comparisonBase: any GitComparisonBaseResolving
    private let fileReader: any FileReading

    init(
        runner: GitCommandRunner = GitCommandRunner(),
        repository: any GitRepositoryReading = GitRepository(),
        comparisonBase: (any GitComparisonBaseResolving)? = nil,
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.runner = runner
        self.repository = repository
        self.fileReader = fileReader
        // 既定は runner を共有する。別の runner を渡された経路(テスト・タイムアウト調整)で
        // 基準の解決だけが本番の runner を使うと、そこだけ別のタイムアウトで動く。
        self.comparisonBase = comparisonBase ?? GitComparisonBaseResolver(runner: runner)
    }

    func indexFingerprint(forRepositoryAt root: URL) -> Date? {
        repository.indexFingerprint(at: root)
    }

    func status(forRepositoryAt root: URL) -> GitStatusSnapshot? {
        // `--no-optional-locks` は必須。既定の status は index を refresh して
        // `.git/index` の mtime を書き換えうるため、fingerprint による無効化(Phase 2)と
        // 組み合わせると「status 実行 → fingerprint 変化 → 再取得」の自己励振ループになる。
        let outcome = runner.run(
            ["--no-optional-locks", "status", "--porcelain=v2", "-z"], in: root
        )
        switch outcome {
        case let .output(data):
            let parsed = Self.parsePorcelainV2(data)
            var statuses: [String: GitFileStatus] = [:]
            statuses.reserveCapacity(parsed.entries.count)
            for (relativePath, status) in parsed.entries {
                let url = root.appendingPathComponent(relativePath)
                statuses[url.normalizedPathKey] = status
            }
            // base ブランチからのコミット済み変更。検出できない場合(デフォルトブランチが
            // 分からない・履歴が繋がっていない)はブランチ内変更だけを諦め、
            // staged / unstaged / untracked の表示は続ける。
            for (relativePath, change) in branchChanges(forRepositoryAt: root) {
                let key = root.appendingPathComponent(relativePath).normalizedPathKey
                statuses[key, default: GitFileStatus()].branchChange = change
            }
            return GitStatusSnapshot(
                statuses: statuses,
                indeterminateRoots: indeterminateRoots(at: root, parsed: parsed),
                indexFingerprint: repository.indexFingerprint(at: root),
                indexURL: repository.indexURL(at: root)
            )
        case .rejected:
            // 実行できて非 0(リポジトリ外など)。答えとして確定しているのでキャッシュしてよい。
            return .empty
        case .unavailable:
            return nil
        }
    }

    // MARK: - Boundaries

    /// 親リポジトリの `git status` では配下を答えられない境界のルート(正規化パスキー)。
    ///
    /// 3 系統の和を取る。**どれか 1 つでは足りない**ことを実測で確かめてある。
    ///
    /// 1. `.gitmodules` に登録されたサブモジュール。clean なサブモジュールは
    ///    status に 1 行も出ないため、ここでしか拾えない
    /// 2. status レコードの `<sub>` が `S` 始まり。`.gitmodules` に無い
    ///    (登録前・手で消された)サブモジュールを拾う
    /// 3. 畳まれた未追跡ディレクトリのうち `.git` を持つもの = ネストしたリポジトリ。
    ///    親から見れば未追跡ディレクトリ 1 件で、配下は列挙すらされない
    ///
    /// - Note: `.gitignore` されたネストしたリポジトリは status に 1 行も出ないため
    ///   検出できない(実測)。ignore された内容が「変更のみ表示」に出ないのは
    ///   全ファイル共通の挙動なので、この限界は他と一貫している。
    private func indeterminateRoots(at root: URL, parsed: ParsedStatus) -> Set<String> {
        var roots = Set<String>()
        for path in submodulePaths(forRepositoryAt: root) {
            roots.insert(root.appendingPathComponent(path).normalizedPathKey)
        }
        for path in parsed.submodulePaths {
            roots.insert(root.appendingPathComponent(path).normalizedPathKey)
        }
        for (path, status) in parsed.entries where status.isUntracked && path.hasSuffix("/") {
            let directory = root.appendingPathComponent(path)
            guard fileReader.fileExists(at: directory.appendingPathComponent(".git")) else { continue }
            roots.insert(directory.normalizedPathKey)
        }
        return roots
    }

    /// `.gitmodules` に登録されたサブモジュールのルート相対パス。
    ///
    /// `git config --file` に読ませるのは、値の引用・エスケープの解釈を git 本体に
    /// 任せるため(自前で INI を読むと引用符付きのパスを取りこぼす)。
    /// `.gitmodules` が無ければ git は非 0 で終わり、空を返す。
    private func submodulePaths(forRepositoryAt root: URL) -> [String] {
        let file = root.appendingPathComponent(".gitmodules").path
        guard case let .output(data) = runner.run(
            ["config", "-z", "--file", file, "--get-regexp", #"^submodule\..*\.path$"#], in: root
        ) else { return [] }
        return Self.parseConfigValues(data)
    }

    /// `git config -z --get-regexp` の出力から値だけを取り出す。
    ///
    /// `-z` の 1 レコードは `<キー>\n<値>` で、レコード間が NUL 区切り。
    /// キーと値の区切りが改行なのは、値そのものに改行を含められるようにするため
    /// (だから最初の改行だけで分ける)。
    static func parseConfigValues(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true).compactMap { record in
            guard let text = String(bytes: record, encoding: .utf8),
                  let newline = text.firstIndex(of: "\n")
            else { return nil }
            let value = String(text[text.index(after: newline)...])
            return value.isEmpty ? nil : value
        }
    }

    // MARK: - Branch Diff

    /// 現在のブランチが base ブランチから変更したコミット済みファイル(ルート相対パス → 変更種別)。
    /// デフォルトブランチを特定できない場合は空を返す(この機能だけを諦める)。
    /// 基準の解決は `GitComparisonBaseResolving` に集約してある。差分ビューアと
    /// 同じ起点を使うことが、バッジと差分の食い違いを防ぐ唯一の担保(TASK-352)。
    private func branchChanges(forRepositoryAt root: URL) -> [String: GitFileStatus.Change] {
        guard let base = comparisonBase.comparisonBase(forRepositoryAt: root),
              case let .output(diffData) = runner.run(
                  ["diff", "--name-status", "-z", base, "HEAD"], in: root
              )
        else { return [:] }
        return Self.parseNameStatus(diffData)
    }

    /// `git diff --name-status -z` の出力から、変更後のパスと変更種別を取り出す。
    ///
    /// `-z` では「状態」と「パス」が別々の NUL 区切りフィールドとして並ぶ。
    /// 改名・複製(`R100` / `C75`)だけはパスが 2 つ(元 → 先)続くため、
    /// 読み進める数を状態で変える必要がある。
    ///
    /// 種別まで持ち帰るのは、表示側が真偽値から文字を決め打ちできないようにするため。
    /// 以前はパスだけを返しており、ブランチで追加したファイルも M で出ていた(TASK-344)。
    static func parseNameStatus(_ data: Data) -> [String: GitFileStatus.Change] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(bytes: $0, encoding: .utf8) ?? ""
        }
        var changes: [String: GitFileStatus.Change] = [:]
        var index = 0
        while index < fields.count {
            let status = fields[index]
            index += 1
            guard let code = status.first else { continue }
            // 改名・複製は「元パス」「変更後パス」の順。表示対象は変更後だけ。
            let pathCount = (code == "R" || code == "C") ? 2 : 1
            guard index + pathCount <= fields.count else { break }
            let path = fields[index + pathCount - 1]
            index += pathCount
            guard !path.isEmpty else { continue }
            // 解釈できないコード(git の `X`=unknown / `B`=pairing broken)でもエントリは捨てない。
            // 捨てると「変更あり」が「変更なし」と同じ無表示に縮退するため、種別だけを諦める。
            changes[path] = GitFileStatus.Change(porcelainCode: code) ?? .modified
        }
        return changes
    }

    // MARK: - Parsing

    /// パース結果 1 件。パスはルート相対。
    typealias Entry = (path: String, status: GitFileStatus)

    /// `parsePorcelainV2` の結果。表示用の状態と、配下を答えられない境界を分けて返す。
    ///
    /// 境界を `entries` と別に返すのは、両者が**別の問い**への答えだから。
    /// `entries` は「この行にどんな変更があるか」、`submodulePaths` は
    /// 「この行の配下について親リポジトリは何も答えていないか」。
    struct ParsedStatus: Equatable {
        var entries: [Entry] = []
        /// `<sub>` フィールドが `S` 始まりだったレコードのルート相対パス。
        /// **clean なサブモジュールはレコード自体が出ないためここに現れない**
        /// (`GitStatusReader.submodulePaths(forRepositoryAt:)` が `.gitmodules` から補う)。
        var submodulePaths: [String] = []

        static func == (lhs: ParsedStatus, rhs: ParsedStatus) -> Bool {
            lhs.submodulePaths == rhs.submodulePaths
                && lhs.entries.count == rhs.entries.count
                && zip(lhs.entries, rhs.entries).allSatisfy { $0.path == $1.path && $0.status == $1.status }
        }
    }

    /// `git status --porcelain=v2 -z` の出力をリポジトリルート相対パス → 状態へ変換する。
    ///
    /// 実 git を起動せずフィクスチャで検証できるよう、純関数として切り出してある
    /// (`GitRepository.parseWorktreeList` と同じ方針)。
    static func parsePorcelainV2(_ data: Data) -> ParsedStatus {
        // UTF-8 として解釈できないフィールドも空文字として位置を残す。詰めてしまうと
        // 改名レコードの「元パス」の読み飛ばし位置がずれ、以降の対応が全部崩れる。
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(bytes: $0, encoding: .utf8) ?? ""
        }
        var result = ParsedStatus()
        var index = 0
        while index < fields.count {
            let record = fields[index]
            index += 1
            // 改名/複製(`2`)は「元パス」が次の NUL 区切りフィールドとして続くため読み飛ばす。
            if record.first == "2" { index += 1 }
            if let path = submodulePath(in: record) { result.submodulePaths.append(path) }
            guard let entry = parseRecord(record) else { continue }
            result.entries.append(entry)
        }
        return result
    }

    /// レコードの手前のフィールド数。パスの位置と `<sub>` の読み出しに共通で使う。
    /// 表示対象にならないレコード(`?` / `!` / ヘッダ)は nil。
    private static func fieldsBeforePath(for record: String) -> Int? {
        switch record.first {
        // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
        case "1": 8
        // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>
        case "2": 9
        // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
        case "u": 10
        default: nil
        }
    }

    /// レコードがサブモジュール(gitlink)を指しているならそのルート相対パス。
    ///
    /// **`parseRecord` の結果とは独立に読む**のが要点。XY が clean で表示対象に
    /// ならないレコードでも、`<sub>` が `S` 始まりならそこは境界であり、配下について
    /// 親リポジトリは何も答えていない。表示対象かどうかで境界の検出を左右させると、
    /// 「バッジが出ないサブモジュールの配下だけが黙って消える」が残る。
    private static func submodulePath(in record: String) -> String? {
        guard let fieldsBeforePath = fieldsBeforePath(for: record) else { return nil }
        let parts = record.split(
            separator: " ", maxSplits: fieldsBeforePath, omittingEmptySubsequences: false
        )
        guard parts.count == fieldsBeforePath + 1, parts[2].first == "S" else { return nil }
        let path = String(parts[fieldsBeforePath])
        return path.isEmpty ? nil : path
    }

    /// 1 レコードを解釈する。表示対象でなければ nil
    /// ("!"=ignored / "#"=ヘッダ / 変更なし / 空フィールド)。
    private static func parseRecord(_ record: String) -> Entry? {
        if let fieldsBeforePath = fieldsBeforePath(for: record) {
            return parseChangedEntry(record, fieldsBeforePath: fieldsBeforePath)
        }
        // ? <path>
        return record.first == "?" ? parseUntrackedEntry(record) : nil
    }

    private static func parseUntrackedEntry(_ record: String) -> Entry? {
        let path = String(record.dropFirst(2))
        guard !path.isEmpty else { return nil }
        return (path, GitFileStatus(indexChange: nil, worktreeChange: nil, isUntracked: true))
    }

    /// XY コードを持つレコード(`1` / `2` / `u`)を 1 件解釈する。
    /// - Parameter fieldsBeforePath: パスの手前にある空白区切りフィールドの数。
    private static func parseChangedEntry(
        _ record: String, fieldsBeforePath: Int
    ) -> (path: String, status: GitFileStatus)? {
        let parts = record.split(
            separator: " ", maxSplits: fieldsBeforePath, omittingEmptySubsequences: false
        )
        guard parts.count == fieldsBeforePath + 1 else { return nil }
        let path = String(parts[fieldsBeforePath])
        guard !path.isEmpty else { return nil }
        let code = parts[1]
        guard code.count == 2 else { return nil }
        let status = GitFileStatus(
            indexChange: GitFileStatus.Change(porcelainCode: code[code.startIndex]),
            worktreeChange: GitFileStatus.Change(porcelainCode: code[code.index(after: code.startIndex)])
        )
        guard !status.isClean else { return nil }
        return (path, status)
    }
}
