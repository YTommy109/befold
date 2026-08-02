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
    /// 取得時点の `.git/index` の最終更新日時。Phase 2 でキャッシュ無効化に使う。
    var indexFingerprint: Date?

    static let empty = GitStatusSnapshot(statuses: [:], indexFingerprint: nil)
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
}

/// `git status --porcelain=v2` で状態を読む本番実装。
struct GitStatusReader: GitStatusReading {
    private let runner: GitCommandRunner
    private let repository: any GitRepositoryReading

    init(runner: GitCommandRunner = GitCommandRunner(), repository: any GitRepositoryReading = GitRepository()) {
        self.runner = runner
        self.repository = repository
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
            let entries = Self.parsePorcelainV2(data)
            var statuses: [String: GitFileStatus] = [:]
            statuses.reserveCapacity(entries.count)
            for (relativePath, status) in entries {
                let url = root.appendingPathComponent(relativePath)
                statuses[url.normalizedPathKey] = status
            }
            return GitStatusSnapshot(
                statuses: statuses, indexFingerprint: repository.indexFingerprint(at: root)
            )
        case .rejected:
            // 実行できて非 0(リポジトリ外など)。答えとして確定しているのでキャッシュしてよい。
            return .empty
        case .unavailable:
            return nil
        }
    }

    // MARK: - Parsing

    /// パース結果 1 件。パスはリポジトリルート相対。
    typealias Entry = (path: String, status: GitFileStatus)

    /// `git status --porcelain=v2 -z` の出力をリポジトリルート相対パス → 状態へ変換する。
    ///
    /// 実 git を起動せずフィクスチャで検証できるよう、純関数として切り出してある
    /// (`GitRepository.parseWorktreeList` と同じ方針)。
    static func parsePorcelainV2(_ data: Data) -> [Entry] {
        // UTF-8 として解釈できないフィールドも空文字として位置を残す。詰めてしまうと
        // 改名レコードの「元パス」の読み飛ばし位置がずれ、以降の対応が全部崩れる。
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(bytes: $0, encoding: .utf8) ?? ""
        }
        var result: [Entry] = []
        var index = 0
        while index < fields.count {
            let record = fields[index]
            index += 1
            // 改名/複製(`2`)は「元パス」が次の NUL 区切りフィールドとして続くため読み飛ばす。
            if record.first == "2" { index += 1 }
            guard let entry = parseRecord(record) else { continue }
            result.append(entry)
        }
        return result
    }

    /// 1 レコードを解釈する。表示対象でなければ nil
    /// ("!"=ignored / "#"=ヘッダ / 変更なし / 空フィールド)。
    private static func parseRecord(_ record: String) -> Entry? {
        switch record.first {
        // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
        case "1": parseChangedEntry(record, fieldsBeforePath: 8)
        // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>
        case "2": parseChangedEntry(record, fieldsBeforePath: 9)
        // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
        case "u": parseChangedEntry(record, fieldsBeforePath: 10)
        // ? <path>
        case "?": parseUntrackedEntry(record)
        default: nil
        }
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
