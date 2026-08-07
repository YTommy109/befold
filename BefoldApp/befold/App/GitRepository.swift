import BefoldKit
import Foundation

/// リポジトリ検出の結果。「git 管理外」という確定した答えと「git を実行できず不明」を
/// 区別する(キャッシュしてよいのは前者だけで、後者を覚えると一時的な失敗が固定化する)。
enum GitRootLookup: Sendable, Equatable {
    case root(URL)
    case notARepository
    case undetermined

    /// 検出できたルート。管理外・判定不能はいずれも nil。
    var foundRoot: URL? {
        guard case let .root(url) = self else { return nil }
        return url
    }
}

/// リポジトリの表示 identity。ラベルと、本体(main)リポジトリのルート URL を併せて持つ。
/// worktree を開いている場合でも本体を起点に兄弟 worktree を列挙できるようにするため、
/// ラベル生成の途中で判明する本体ルートを捨てずに公開する。
struct RepositoryIdentity: Sendable, Equatable {
    var label: String
    var mainRoot: URL
}

/// リポジトリに属する作業ツリー 1 件。
struct GitWorktree: Sendable, Equatable {
    var root: URL
    /// 本体リポジトリの作業ツリーなら true(`git worktree list` の先頭)。
    var isMain: Bool
    /// チェックアウト中のブランチ名(`refs/heads/` を除いた短縮形)。
    /// detached HEAD や bare では nil。
    var branch: String?

    /// メニュー表示名。ディレクトリ名が `etc` のように機械的なこともあるため
    /// ブランチ名を主軸にし、ディレクトリ名を括弧で併記する(本体ラベルの表記と揃える)。
    /// ブランチが無い(detached/bare)場合はディレクトリ名だけにする。
    var displayName: String {
        let directoryName = root.lastPathComponent
        guard let branch else { return directoryName }
        return "\(branch) (\(directoryName))"
    }
}

/// git リポジトリの検出・identity・追跡ファイル列挙を提供する読み取りシーム。
/// 差し替え可能にしてキャッシュ層(GitCommandFileIndex)を純粋にテストできるようにする。
protocol GitRepositoryReading: Sendable {
    /// url を含む作業ツリールートの検出結果。
    func root(forFileAt url: URL) -> GitRootLookup
    /// root 配下の追跡ファイル絶対 URL 一覧(作業ツリー)。
    /// git を実行できなかった場合は nil(追跡ファイルが 0 件であることと区別する)。
    func trackedFiles(at root: URL) -> [URL]?
    /// 追跡集合が変わると変化する軽量シグネチャ(.git/index の最終更新日時)。
    func indexFingerprint(at root: URL) -> Date?
    /// `.git/index` の実パス。worktree では `.git` がファイルで実 gitdir を指すため、
    /// 呼び出し側が `root/.git/index` と組み立てても当たらない。監視対象の指定に使う。
    func indexURL(at root: URL) -> URL
}

extension GitRepositoryReading {
    /// 通常のリポジトリ配置(`<root>/.git/index`)を仮定した既定。worktree / submodule の
    /// `.git` ファイル経由の解決が要る実装(`GitRepository`)だけが上書きする。
    /// テスト用フェイクがこの一点のために実装を持たされるのを避けるための既定でもある。
    func indexURL(at root: URL) -> URL {
        root.appendingPathComponent(".git").appendingPathComponent("index")
    }
}

/// git コマンド + ファイル stat による GitRepositoryReading 実装。
/// ブランチ/ワークツリー切替・差分など将来の git 機能の拡張点。
struct GitRepository: GitRepositoryReading {
    private let runner: any GitCommandRunning
    private let fileReader: FileReading

    init(runner: any GitCommandRunning = GitCommandRunner(), fileReader: FileReading = DefaultFileReader()) {
        self.runner = runner
        self.fileReader = fileReader
    }

    func root(forFileAt url: URL) -> GitRootLookup {
        let dir = url.deletingLastPathComponent()
        switch runner.run(["rev-parse", "--show-toplevel"], in: dir) {
        case let .output(data):
            // 出力が読めない/空なら答えが取れていないので、管理外と断定せず不明に倒す。
            guard let out = String(data: data, encoding: .utf8),
                  let first = out.split(separator: "\n").first
            else { return .undetermined }
            return .root(URL(fileURLWithPath: String(first), isDirectory: true).standardizedFileURL)
        case .rejected:
            return .notARepository
        case .unavailable:
            return .undetermined
        }
    }

    func trackedFiles(at root: URL) -> [URL]? {
        guard case let .output(data) = runner.run(["ls-files", "-z"], in: root) else { return nil }
        return data.split(separator: 0).compactMap { slice in
            guard let rel = String(data: Data(slice), encoding: .utf8), !rel.isEmpty else { return nil }
            return root.appendingPathComponent(rel).standardizedFileURL
        }
    }

    /// add/rm/checkout/commit で `.git/index` が更新されるため、その最終更新日時を
    /// キャッシュ無効化シグネチャに使う。外部のブランチ/ワークツリー切替を subprocess
    /// なしのファイル stat だけで検知できる。
    func indexFingerprint(at root: URL) -> Date? {
        fileReader.modificationDate(at: indexURL(at: root))
    }

    func indexURL(at root: URL) -> URL {
        gitDirectory(at: root).appendingPathComponent("index")
    }

    /// メニュー表示用のラベルと本体リポジトリのルートを返す。
    /// `--git-common-dir` と `--git-dir` を比較し、一致すれば本体、不一致なら worktree と判定する
    /// (worktree の `.git` はファイルで実 gitdir を指すため両者が食い違う)。
    /// worktree の場合、本体ルートは共通 gitdir の親ディレクトリ。
    /// git 呼び出しに失敗した場合は本体扱い(ディレクトリ名 + 自身のルート)に縮退する。
    func repositoryIdentity(forRoot root: URL) -> RepositoryIdentity {
        let standardizedRoot = root.standardizedFileURL
        let asMainRepository = RepositoryIdentity(
            label: standardizedRoot.lastPathComponent, mainRoot: standardizedRoot
        )
        guard case let .output(data) = runner.run(["rev-parse", "--git-common-dir", "--git-dir"], in: root),
              let text = String(data: data, encoding: .utf8)
        else { return asMainRepository }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count == 2 else { return asMainRepository }
        let commonDir = URL(fileURLWithPath: lines[0], relativeTo: root).standardizedFileURL
        let gitDir = URL(fileURLWithPath: lines[1], relativeTo: root).standardizedFileURL
        guard commonDir.path != gitDir.path else { return asMainRepository }
        let mainRoot = commonDir.deletingLastPathComponent().standardizedFileURL
        return RepositoryIdentity(
            label: "\(mainRoot.lastPathComponent) (\(standardizedRoot.lastPathComponent))",
            mainRoot: mainRoot
        )
    }

    /// root が属するリポジトリの作業ツリー一覧を返す。先頭(本体)が `isMain == true`。
    /// git を実行できない・出力を解釈できない場合は空配列に縮退し、
    /// 呼び出し側が worktree 非表示のフラット表示へ落とせるようにする。
    func worktrees(forRoot root: URL) -> [GitWorktree] {
        guard case let .output(data) = runner.run(["worktree", "list", "--porcelain"], in: root),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return Self.parseWorktreeList(text)
    }

    /// `git worktree list --porcelain` の出力をパースする純関数。git 実行を経ないため
    /// インメモリのフィクスチャで網羅的に検証できる(実 git の spawn はスモーク 1 本に任せる)。
    /// porcelain 形式は 1 エントリが `worktree <path>` 行で始まり、続く属性行
    /// (HEAD/branch/bare/detached)を経て空行で区切られる。表示に使うのは path と branch のみ。
    static func parseWorktreeList(_ text: String) -> [GitWorktree] {
        var result: [GitWorktree] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("worktree ") {
                let path = String(line.dropFirst("worktree ".count)).trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { continue }
                result.append(
                    GitWorktree(
                        root: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL,
                        isMain: result.isEmpty
                    )
                )
            } else if line.hasPrefix("branch "), !result.isEmpty {
                let ref = String(line.dropFirst("branch ".count)).trimmingCharacters(in: .whitespaces)
                let name = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                result[result.count - 1].branch = name.isEmpty ? nil : name
            }
        }
        return result
    }

    /// root/.git がディレクトリならそれ、ファイル(worktree/submodule)なら
    /// `gitdir: <path>` を解決した実 gitdir を返す。
    private func gitDirectory(at root: URL) -> URL {
        let dotGit = root.appendingPathComponent(".git")
        if fileReader.isDirectory(at: dotGit) { return dotGit }
        guard fileReader.isExistingFile(at: dotGit),
              let content = try? fileReader.readString(from: dotGit)
        else { return dotGit }
        // 「gitdir: 行を探す」と「その行を解釈する」を分ける。
        let gitdirLine = content
            .split(separator: "\n")
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("gitdir:") }
        guard let gitdirLine else { return dotGit }

        let path = String(gitdirLine.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            : root.appendingPathComponent(path).standardizedFileURL
    }
}
