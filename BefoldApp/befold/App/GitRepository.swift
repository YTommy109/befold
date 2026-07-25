import BefoldKit
import Foundation

/// git リポジトリの検出・identity・追跡ファイル列挙を提供する読み取りシーム。
/// 差し替え可能にしてキャッシュ層(GitCommandFileIndex)を純粋にテストできるようにする。
protocol GitRepositoryReading: Sendable {
    /// url を含む作業ツリールート。git 管理外なら nil。
    func root(forFileAt url: URL) -> URL?
    /// root 配下の追跡ファイル絶対 URL 一覧(作業ツリー)。
    func trackedFiles(at root: URL) -> [URL]
    /// 追跡集合が変わると変化する軽量シグネチャ(.git/index の最終更新日時)。
    func indexFingerprint(at root: URL) -> Date?
}

/// git コマンド + ファイル stat による GitRepositoryReading 実装。
/// ブランチ/ワークツリー切替・差分など将来の git 機能の拡張点。
struct GitRepository: GitRepositoryReading {
    private let runner: GitCommandRunner
    private let fileReader: FileReading

    init(runner: GitCommandRunner = GitCommandRunner(), fileReader: FileReading = DefaultFileReader()) {
        self.runner = runner
        self.fileReader = fileReader
    }

    func root(forFileAt url: URL) -> URL? {
        let dir = url.deletingLastPathComponent()
        guard let out = runner.runString(["rev-parse", "--show-toplevel"], in: dir),
              let first = out.split(separator: "\n").first
        else { return nil }
        return URL(fileURLWithPath: String(first), isDirectory: true).standardizedFileURL
    }

    func trackedFiles(at root: URL) -> [URL] {
        guard let data = runner.run(["ls-files", "-z"], in: root) else { return [] }
        return data.split(separator: 0).compactMap { slice in
            guard let rel = String(data: Data(slice), encoding: .utf8), !rel.isEmpty else { return nil }
            return root.appendingPathComponent(rel).standardizedFileURL
        }
    }

    /// add/rm/checkout/commit で `.git/index` が更新されるため、その最終更新日時を
    /// キャッシュ無効化シグネチャに使う。外部のブランチ/ワークツリー切替を subprocess
    /// なしのファイル stat だけで検知できる。
    func indexFingerprint(at root: URL) -> Date? {
        fileReader.modificationDate(at: gitDirectory(at: root).appendingPathComponent("index"))
    }

    /// root/.git がディレクトリならそれ、ファイル(worktree/submodule)なら
    /// `gitdir: <path>` を解決した実 gitdir を返す。
    private func gitDirectory(at root: URL) -> URL {
        let dotGit = root.appendingPathComponent(".git")
        if fileReader.isDirectory(at: dotGit) { return dotGit }
        guard fileReader.isExistingFile(at: dotGit),
              let content = try? fileReader.readString(from: dotGit)
        else { return dotGit }
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("gitdir:") else { continue }
            let path = String(trimmed.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            }
            return root.appendingPathComponent(path).standardizedFileURL
        }
        return dotGit
    }
}
