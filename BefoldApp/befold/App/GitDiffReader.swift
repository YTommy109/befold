import Foundation

/// 表示中のファイル 1 つ分の差分を取得する。
///
/// 実装は subprocess を起こすため、必ずメインアクターの外で呼ぶこと
/// (`GitStatusReading` と同じ契約)。
protocol GitDiffReading: Sendable {
    /// - Returns: 取得できた結果。git を動かせなかった(`.unavailable`)場合は nil。
    ///   nil は「不明」であって「差分なし」ではないため、呼び出し側はキャッシュしてはならない。
    func diff(forFileAt url: URL, in root: URL) -> GitFileDiff?
}

/// `git diff HEAD -- <path>` で unified diff を読む本番実装。
struct GitDiffReader: GitDiffReading {
    /// 描画に載せる差分の上限バイト数。
    ///
    /// 差分取得は保存のたびに走りうるため、生成ファイルの全書き換えのような巨大な diff を
    /// そのまま WebView へ送るとメインスレッドが張り付く。上限は表示側の判断材料として返す。
    static let maxDiffBytes = 1 << 20

    /// `-U` に渡す文脈行数。ファイル全体が 1 つのハンクに収まる十分な大きさにする
    /// (変更の周辺だけを抜き出すと、ビューアとして前後が読めなくなるため)。
    /// これより行数の多いファイルは上限バイト数で先に弾かれる。
    static let wholeFileContextLines = 1_000_000

    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func diff(forFileAt url: URL, in root: URL) -> GitFileDiff? {
        // 比較対象を index ではなく HEAD にしている。ビューアが表示しているのは作業ツリーの
        // 内容で、ユーザーが見たいのは「最後のコミットから何を変えたか」。index 比較だと
        // ステージ済みの変更が差分から消え、サイドバーのバッジが変更ありを示しているのに
        // 差分だけ空、という食い違いになる。
        //
        // `--no-optional-locks` は status と同じ理由で必須(index の refresh で `.git/index` の
        // mtime が動くと、それを監視している側と自己励振ループになる)。
        // 文脈行は全文を含む大きさにする。ビューアは「ファイルを読む」ための画面で、
        // 変更の周辺だけを抜き出すと前後が飛んで読めなくなる。全文を 1 つのハンクに
        // 収めることで、通常のソース表示と同じ見え方のまま変更行に印が付く
        // (結果としてハンクの区切りも出なくなる)。
        let arguments = [
            "--no-optional-locks", "diff", "--no-color", "--no-ext-diff",
            "-U\(Self.wholeFileContextLines)", "HEAD",
            "--", url.path,
        ]
        switch runner.run(arguments, in: root) {
        case .unavailable:
            return nil
        case .rejected:
            return classifyRejection(in: root)
        case let .output(data):
            return classifyOutput(data, forFileAt: url, in: root)
        }
    }

    /// `diff HEAD` が非 0 で終わる理由は「リポジトリ外」と「コミットが無い」の 2 つ。
    /// 出力が無いことからは区別できないため、git-dir が引けるかという事実で判定する。
    private func classifyRejection(in root: URL) -> GitFileDiff? {
        switch runner.run(["rev-parse", "--git-dir"], in: root) {
        case .unavailable: nil
        case .rejected: .notInRepository
        case .output: .noCommits
        }
    }

    private func classifyOutput(_ data: Data, forFileAt url: URL, in root: URL) -> GitFileDiff? {
        if data.count > Self.maxDiffBytes { return .tooLarge(byteCount: data.count) }
        // 出力が空でも「変更なし」とは限らない。未追跡ファイルは HEAD に対応物が無く、
        // diff は成功して空を返す。空かどうかではなく追跡されているかで判定する。
        if data.isEmpty { return isTracked(url, in: root).map { $0 ? .noChanges : .untracked } }
        guard let text = String(data: data, encoding: .utf8) else { return .binary }
        return Self.isBinaryDiff(text) ? .binary : .diff(text)
    }

    /// - Returns: 追跡されていれば true。判定できなければ nil。
    private func isTracked(_ url: URL, in root: URL) -> Bool? {
        switch runner.run(["ls-files", "--error-unmatch", "-z", "--", url.path], in: root) {
        case .unavailable: nil
        case .rejected: false
        case .output: true
        }
    }

    /// git はバイナリの差分本文を出さず、ヘッダに続けて `Binary files a/… and b/… differ` を書く。
    /// 本文の行は必ず `+` / `-` / ` ` で始まるため、行頭一致で判定できる。
    static func isBinaryDiff(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0.hasPrefix("Binary files ") || $0.hasPrefix("GIT binary patch") }
    }
}
