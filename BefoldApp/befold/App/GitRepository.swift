import BefoldKit
import Foundation
import libgit2

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
    /// 本体リポジトリの作業ツリーなら true。
    /// 一覧の先頭に来るかではなく、共通 gitdir から解決した本体そのものかで決まる。
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

/// libgit2 + ファイル stat による GitRepositoryReading 実装。
/// ブランチ/ワークツリー切替・差分など将来の git 機能の拡張点。
///
/// リポジトリを開くのは `GitLibrary.withRepository(at:_:)` 経由に限る(ADR 0005)。
/// 開けなかった場合の縮退は各メソッドの doc に個別に書く。
///
/// ## `indexFingerprint` / `indexURL` を libgit2 に寄せない理由
///
/// `git_repository_path` を使えば `gitDirectory(at:)` の手書きパーサ(`.git` ファイルの
/// `gitdir:` 行を解決する処理)を消せるが、この 2 つは「git を起こすか」を決める門番であり
/// 最も高頻度に走る。`GitStatusReader.indexFingerprint(forRepositoryAt:)` はサイドバーの
/// `.git` 監視コールバックごと、`GitCommandFileIndex.trackedFileIndex(forFileAt:)` は
/// 文書の参照解決ごとに毎回生で通る。ここを libgit2 に寄せると、監視イベント頻度 ×
/// ウィンドウ数でリポジトリオープンが増える。stat 1 回のまま据え置く。
struct GitRepository: GitRepositoryReading {
    private let fileReader: FileReading

    init(fileReader: FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    /// 作業ツリールートを解決する。開けなかった場合は `.undetermined` へ倒し、
    /// 「git 管理外であることが確定した」`.notARepository` と区別する
    /// (キャッシュしてよいのは後者だけ。`GitCommandFileIndex.resolvedRoot(forFileAt:)`)。
    func root(forFileAt url: URL) -> GitRootLookup {
        let outcome = GitLibrary.withRepository(at: url.deletingLastPathComponent()) { repository in
            Self.workdirURL(of: repository)
        }
        switch outcome {
        case let .success(root?):
            return .root(root)
        case .success(nil):
            // bare リポジトリには作業ツリーが無い。外部 git 方式でも
            // `rev-parse --show-toplevel` が非 0 終了し `.notARepository` へ落ちていた。
            return .notARepository
        case .failure(.notARepository):
            return .notARepository
        case .failure(.unusable):
            return .undetermined
        }
    }

    /// index に載っているパスを列挙する。`git ls-files` と同じく submodule の gitlink も含む。
    /// リポジトリを開けない・index を読めない場合は nil(追跡ファイルが 0 件であることと区別する)。
    ///
    /// index からは生バイトで取るため、`core.quotepath` によるファイル名のエスケープを
    /// 解く必要が無い(外部 git 方式が `ls-files -z` を使っていた理由がそのまま消える)。
    func trackedFiles(at root: URL) -> [URL]? {
        let outcome = GitLibrary.withRepository(at: root) { repository -> [URL]? in
            var index: OpaquePointer?
            guard git_repository_index(&index, repository) == 0, let index else { return nil }
            defer { git_index_free(index) }
            return (0 ..< git_index_entrycount(index)).compactMap { position in
                guard let path = git_index_get_byindex(index, position)?.pointee.path else { return nil }
                return root.appendingPathComponent(String(cString: path)).standardizedFileURL
            }
        }
        return (try? outcome.get()) ?? nil
    }

    /// add/rm/checkout/commit で `.git/index` が更新されるため、その最終更新日時を
    /// キャッシュ無効化シグネチャに使う。外部のブランチ/ワークツリー切替を
    /// リポジトリを開かずファイル stat だけで検知できる。
    func indexFingerprint(at root: URL) -> Date? {
        fileReader.modificationDate(at: indexURL(at: root))
    }

    func indexURL(at root: URL) -> URL {
        gitDirectory(at: root).appendingPathComponent("index")
    }

    /// メニュー表示用のラベルと本体リポジトリのルートを返す。
    /// `git_repository_is_worktree` でリンク worktree かを判定し、worktree なら
    /// 本体ルートを共通 gitdir の親ディレクトリとして解決する。
    /// リポジトリを開けない場合は本体扱い(ディレクトリ名 + 自身のルート)に縮退する。
    func repositoryIdentity(forRoot root: URL) -> RepositoryIdentity {
        let standardizedRoot = root.standardizedFileURL
        let asMainRepository = RepositoryIdentity(
            label: standardizedRoot.lastPathComponent, mainRoot: standardizedRoot
        )
        let outcome = GitLibrary.withRepository(at: root) { repository -> URL? in
            guard git_repository_is_worktree(repository) != 0 else { return nil }
            return Self.mainRootFromCommonDirectory(of: repository)
        }
        guard case let .success(mainRoot) = outcome, let mainRoot else { return asMainRepository }
        return RepositoryIdentity(
            label: "\(mainRoot.lastPathComponent) (\(standardizedRoot.lastPathComponent))",
            mainRoot: mainRoot
        )
    }

    /// root が属するリポジトリの作業ツリー一覧を返す。先頭が本体(`isMain == true`)。
    /// リポジトリを開けない場合は空配列に縮退し、
    /// 呼び出し側が worktree 非表示のフラット表示へ落とせるようにする。
    ///
    /// `git_worktree_list` はリンク worktree だけを返し本体を含まないため、本体は
    /// 共通 gitdir から自前で組み立てる。`isMain` は一覧の位置ではなくこの出自で決まる。
    ///
    /// `root` が本体そのものなら開き直さない。起動時に「最近使ったリポジトリ」の
    /// 本体ルート全件をループする(`AppDelegate` の `worktreeCatalog.refresh`)ため、
    /// 1 回あたりのオープン回数がエントリ件数倍で効く。
    func worktrees(forRoot root: URL) -> [GitWorktree] {
        let outcome = GitLibrary.withRepository(at: root) { repository -> [GitWorktree] in
            guard git_repository_is_worktree(repository) != 0 else {
                return Self.worktrees(inMainRepository: repository)
            }
            guard let commonDir = Self.commonDirectoryURL(of: repository) else { return [] }
            let fromMain = GitLibrary.withRepository(at: commonDir) { main in
                Self.worktrees(inMainRepository: main)
            }
            return (try? fromMain.get()) ?? []
        }
        return (try? outcome.get()) ?? []
    }

    /// 本体リポジトリを起点に、本体 + リンク worktree を並べる。
    private static func worktrees(inMainRepository main: OpaquePointer) -> [GitWorktree] {
        // bare には作業ツリーが無いので gitdir 自体をルートとして見せる
        // (`git worktree list` が bare リポジトリのパスを先頭に出すのと同じ表示)。
        guard let mainRoot = workdirURL(of: main) ?? commonDirectoryURL(of: main) else { return [] }
        var result = [GitWorktree(root: mainRoot, isMain: true, branch: branchName(of: main))]
        var names = git_strarray()
        guard git_worktree_list(&names, main) == 0 else { return result }
        defer { git_strarray_dispose(&names) }
        for position in 0 ..< names.count {
            guard let name = names.strings?[position] else { continue }
            var worktree: OpaquePointer?
            guard git_worktree_lookup(&worktree, main, name) == 0, let worktree else { continue }
            defer { git_worktree_free(worktree) }
            guard let path = git_worktree_path(worktree) else { continue }
            let root = URL(fileURLWithPath: String(cString: path), isDirectory: true).standardizedFileURL
            result.append(GitWorktree(root: root, isMain: false, branch: branchName(atWorktreeRoot: root)))
        }
        return result
    }

    /// `git_worktree_*` はチェックアウト中のブランチ名を返さないため、その worktree を
    /// 開き直して HEAD から読む。開けなければブランチ無し扱い(表示はディレクトリ名だけ)。
    private static func branchName(atWorktreeRoot root: URL) -> String? {
        let outcome = GitLibrary.withRepository(at: root) { branchName(of: $0) }
        return (try? outcome.get()) ?? nil
    }

    /// HEAD の短縮ブランチ名。detached・unborn・bare では nil。
    private static func branchName(of repository: OpaquePointer) -> String? {
        guard git_repository_head_detached(repository) == 0 else { return nil }
        var head: OpaquePointer?
        guard git_repository_head(&head, repository) == 0, let head else { return nil }
        defer { git_reference_free(head) }
        guard let name = git_reference_shorthand(head) else { return nil }
        let branch = String(cString: name)
        return branch.isEmpty ? nil : branch
    }

    /// 作業ツリーのルート。bare では nil。
    private static func workdirURL(of repository: OpaquePointer) -> URL? {
        guard let path = git_repository_workdir(repository) else { return nil }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true).standardizedFileURL
    }

    /// 共通 gitdir(`<本体>/.git`)。リンク worktree から呼んでも本体側を指す。
    private static func commonDirectoryURL(of repository: OpaquePointer) -> URL? {
        guard let path = git_repository_commondir(repository) else { return nil }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true).standardizedFileURL
    }

    /// 共通 gitdir の親 = 本体リポジトリのルート。
    private static func mainRootFromCommonDirectory(of repository: OpaquePointer) -> URL? {
        commonDirectoryURL(of: repository)?.deletingLastPathComponent().standardizedFileURL
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
