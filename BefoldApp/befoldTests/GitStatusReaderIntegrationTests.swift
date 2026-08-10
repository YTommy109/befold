@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 実 git が作ったリポジトリを `GitStatusReader`(libgit2 実装)が読めることの
/// Integration テスト。
///
/// libgit2 化で「git の出力テキストをパースする純関数」が無くなったため、状態の
/// 網羅もここが担う(フィクスチャで代替できる部分は無い)。
struct GitStatusReaderIntegrationTests {
    private func makeReader() -> GitStatusReader {
        GitStatusReader()
    }

    @Test("staged / unstaged / untracked を実 git の出力から判別する")
    func classifiesRealRepositoryStatuses() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "staged.swift", in: temp.url)
        try GitTestRepo.commitFile(named: "unstaged.swift", in: temp.url)
        try GitTestRepo.stageChange(to: "staged.swift", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("unstaged.swift", in: temp.url)
        try GitTestRepo.addUntrackedFile(named: "new.swift", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        func status(_ name: String) -> GitFileStatus? {
            snapshot.statuses[temp.url.appendingPathComponent(name).normalizedPathKey]
        }
        #expect(status("staged.swift") == GitFileStatus(indexChange: .modified, worktreeChange: nil))
        #expect(status("unstaged.swift") == GitFileStatus(indexChange: nil, worktreeChange: .modified))
        #expect(status("new.swift")?.isUntracked == true)
        // `.git/index` の fingerprint を同梱して返す(Phase 2 のキャッシュ無効化で使う)。
        #expect(snapshot.indexFingerprint != nil)
    }

    /// 境界の検出は 3 系統の和で、フィクスチャで押さえられるのはパースまで。
    /// 「clean なサブモジュールは status に 1 行も出ない」「ネストしたリポジトリは
    /// 未追跡ディレクトリ 1 件へ畳まれる」という git 側の挙動そのものに依存するため、
    /// 実 git で 1 本だけ通しで確かめる(TASK-403)。
    @Test("clean なサブモジュールとネストしたリポジトリを境界として検出する")
    func detectsSubmoduleAndNestedRepositoryBoundaries() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let child = try TempDir()
        defer { withExtendedLifetime(child) {} }
        GitTestRepo.initRepository(at: child.url)
        try GitTestRepo.commitFile(named: "a.txt", in: child.url)

        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "root.txt", in: temp.url)
        // file:// 越しの submodule add は既定で拒否されるため明示的に許可する。
        GitTestRepo.run(
            ["-c", "protocol.file.allow=always", "submodule", "add", child.url.path, "sub"],
            in: temp.url
        )
        GitTestRepo.run(["commit", "-m", "add submodule"], in: temp.url)
        // 親から見て未追跡ディレクトリ 1 件へ畳まれる、独立したリポジトリ。
        let nested = temp.url.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        GitTestRepo.initRepository(at: nested)
        try GitTestRepo.commitFile(named: "b.txt", in: nested)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.indeterminateRoots.contains(
            temp.url.appendingPathComponent("sub").normalizedPathKey
        ))
        #expect(snapshot.indeterminateRoots.contains(nested.normalizedPathKey))
        // サブモジュールは clean なので status に 1 行も出ない = 検出の出所は
        // `.gitmodules` 側であることの確認(ここが空でも境界は立っている)。
        #expect(snapshot.statuses[temp.url.appendingPathComponent("sub").normalizedPathKey] == nil)
    }

    /// `.gitmodules` にも `.git/config` にも登録が無い gitlink でも境界として検出できること。
    ///
    /// 外部 git 方式では porcelain の `<sub>` フィールドが `S` 始まりかで拾っていた系統。
    /// libgit2 では `git_submodule_foreach` が index の gitlink まで列挙するため、
    /// 登録の有無によらず同じ集合になる(この前提が崩れたらここが落ちる)。
    ///
    /// 併せて、中身が変更されたサブモジュールにバッジが付くことも固定する。
    /// `GIT_STATUS_OPT_EXCLUDE_SUBMODULES` を足すと status のエントリが 1 件も出なくなり、
    /// バッジが黙って消える(実測)。それを検知するのがこのテストの後半。
    @Test("登録されていない gitlink も境界として検出し、変更されたサブモジュールにバッジを出す")
    func showsBadgeForDirtySubmodule() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let child = try TempDir()
        defer { withExtendedLifetime(child) {} }
        GitTestRepo.initRepository(at: child.url)
        try GitTestRepo.commitFile(named: "a.txt", in: child.url)

        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "root.txt", in: temp.url)
        GitTestRepo.run(
            ["-c", "protocol.file.allow=always", "submodule", "add", child.url.path, "sub"], in: temp.url
        )
        GitTestRepo.run(["commit", "-m", "add submodule"], in: temp.url)
        // 登録を両方から消す。index の gitlink だけが残った状態を作る。
        GitTestRepo.run(["rm", "-f", ".gitmodules"], in: temp.url)
        GitTestRepo.run(["config", "--remove-section", "submodule.sub"], in: temp.url)
        GitTestRepo.run(["commit", "-m", "drop registration"], in: temp.url)
        // clean な gitlink は status に出ないため、サブモジュール側を汚してエントリを立てる。
        try GitTestRepo.modifyWithoutStaging("a.txt", in: temp.url.appendingPathComponent("sub"))

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.indeterminateRoots.contains(
            temp.url.appendingPathComponent("sub").normalizedPathKey
        ))
        #expect(
            snapshot.statuses[temp.url.appendingPathComponent("sub").normalizedPathKey] != nil,
            "変更されたサブモジュールのバッジが消えている(EXCLUDE_SUBMODULES を設定していないか)"
        )
    }

    // MARK: - 変更種別の写像(旧 porcelain フィクスチャからの移設)

    @Test("staged と unstaged が両立するファイルは両辺の変更種別を保持する")
    func keepsBothSidesWhenStagedAndUnstaged() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "seed.md", in: temp.url)
        // index へ新規追加した後、作業ツリー側だけをさらに書き換える(porcelain の `AM`)。
        try GitTestRepo.stageChange(to: "both.md", contents: "staged", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("both.md", contents: "worktree", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.statuses[temp.url.appendingPathComponent("both.md").normalizedPathKey]
            == GitFileStatus(indexChange: .added, worktreeChange: .modified))
    }

    @Test("削除と改名がそれぞれの変更種別として返る")
    func mapsDeletionAndRename() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "gone.md", contents: "gone", in: temp.url)
        try GitTestRepo.commitFile(named: "old.md", contents: String(repeating: "content\n", count: 20), in: temp.url)
        GitTestRepo.run(["rm", "gone.md"], in: temp.url)
        GitTestRepo.run(["mv", "old.md", "new.md"], in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        func status(_ name: String) -> GitFileStatus? {
            snapshot.statuses[temp.url.appendingPathComponent(name).normalizedPathKey]
        }
        #expect(status("gone.md")?.indexChange == .deleted)
        // 改名検出が効いていれば新パスが .renamed。効かない場合は旧パスの削除 +
        // 新パスの追加になるため、新パス側の種別で判定できる。
        #expect(status("new.md")?.indexChange == .renamed)
        #expect(status("old.md") == nil)
    }

    @Test("未マージのファイルは両辺を unmerged として扱う")
    func mapsUnmergedFiles() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "conflict.md", contents: "base", in: temp.url)
        GitTestRepo.run(["checkout", "-b", "other"], in: temp.url)
        try GitTestRepo.commitChange(to: "conflict.md", contents: "theirs", in: temp.url)
        GitTestRepo.run(["checkout", "-"], in: temp.url)
        try GitTestRepo.commitChange(to: "conflict.md", contents: "ours", in: temp.url)
        GitTestRepo.run(["merge", "other"], in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        let status = snapshot.statuses[temp.url.appendingPathComponent("conflict.md").normalizedPathKey]
        #expect(status?.indexChange == .unmerged)
        #expect(status?.worktreeChange == .unmerged)
    }

    @Test("ignored ファイルと変更の無いファイルはバッジ対象に含めない")
    func skipsIgnoredAndUnchangedFiles() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "unchanged.md", in: temp.url)
        try GitTestRepo.commitFile(named: ".gitignore", contents: "ignored.md\n", in: temp.url)
        try GitTestRepo.addUntrackedFile(named: "ignored.md", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.statuses.isEmpty, "余計なエントリ: \(snapshot.statuses.keys.sorted())")
    }

    /// Reader / Store / SidebarNavigator を本番と同じ組み合わせで繋ぎ、実リポジトリの
    /// 変更がサイドバーのモデルまで届くことを確認する(描画そのものは手動チェック対象)。
    @MainActor
    @Test("実リポジトリの状態がサイドバーのモデルまで届く")
    func deliversRealStatusesToSidebarModel() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.md", in: temp.url)

        let gitFileIndex = GitCommandFileIndex()
        let store = GitStatusStore(
            reader: makeReader(),
            resolveRepositoryRoot: { gitFileIndex.repositoryRoot(forDirectoryAt: $0) }
        )
        let navigator = SidebarNavigator(
            currentDirectory: temp.url,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "GitStatusReaderIntegrationTests")
            ),
            directoryLister: { _, _, _ in [] },
            loadGitStatuses: { directory, policy in
                await store.statuses(forDirectoryAt: directory, policy: policy)
            }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        let key = temp.url.appendingPathComponent("a.md").normalizedPathKey
        #expect(navigator.fileListModel.gitStatus?.fileStatus(at: key)?.worktreeChange == .modified)
    }

    /// TASK-186.2 の中核。`.git/index` の監視から状態の取り直しまでを実物どうしで繋ぎ、
    /// 「git 操作のあと、明示 refresh なしにバッジが変わる」ことを確認する。
    @MainActor
    @Test("git add の後、明示 refresh なしでサイドバーの状態が更新される", testTimeLimit())
    func updatesWithoutExplicitRefreshAfterStaging() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.md", in: temp.url)

        let gitFileIndex = GitCommandFileIndex()
        let store = GitStatusStore(
            reader: makeReader(),
            resolveRepositoryRoot: { gitFileIndex.repositoryRoot(forDirectoryAt: $0) }
        )
        let navigator = SidebarNavigator(
            currentDirectory: temp.url,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "GitStatusIndexWatch")
            ),
            directoryLister: { _, _, _ in [] },
            loadGitStatuses: { directory, policy in
                await store.statuses(forDirectoryAt: directory, policy: policy)
            }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value
        let key = temp.url.appendingPathComponent("a.md").normalizedPathKey
        #expect(navigator.fileListModel.gitStatus?.fileStatus(at: key)?.worktreeChange == .modified)

        // ここから先は明示的な refresh を一切呼ばない。`.git/index` の監視だけが契機。
        GitTestRepo.run(["add", "a.md"], in: temp.url)

        await waitUntilOnMainActor { navigator.fileListModel.gitStatus?.fileStatus(at: key)?.indexChange == .modified }
        #expect(navigator.fileListModel.gitStatus?.fileStatus(at: key)?.worktreeChange == nil)
    }

    /// 自己励振の防止線。status が `.git/index` を書き換えると
    /// 「status → fingerprint 変化 → 監視発火 → status」の輪ができる
    /// (外部 git 方式で `--no-optional-locks` が防いでいたもの)。
    ///
    /// **内容を変えずに mtime だけ動かす**のが要点。内容ごと変えた場合、libgit2 は
    /// `GIT_STATUS_OPT_UPDATE_INDEX` を設定しても index を書かないため、
    /// このフラグを足す退行を検知できない(実測で確認済み)。stat だけが古くなった状態こそが
    /// UPDATE_INDEX の書き込み条件であり、防止線はそこに置かなければ効かない。
    @Test("status 実行は .git/index の fingerprint を変えない")
    func statusDoesNotDisturbIndexFingerprint() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", contents: "same", in: temp.url)
        // 同じ内容で書き直して mtime だけ進める(index の stat キャッシュが古くなる)。
        try GitTestRepo.modifyWithoutStaging("a.md", contents: "same", in: temp.url)
        let reader = makeReader()
        let before = reader.indexFingerprint(forRepositoryAt: temp.url)

        _ = reader.status(forRepositoryAt: temp.url)
        _ = reader.status(forRepositoryAt: temp.url)

        #expect(reader.indexFingerprint(forRepositoryAt: temp.url) == before)
    }

    @Test("変更が無いリポジトリでは空のスナップショットを返す")
    func returnsEmptySnapshotForCleanRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.statuses.isEmpty)
    }

    /// 非リポジトリでは git が非 0 で終わる(`.rejected`)。答えとして確定しているので
    /// nil ではなく空のスナップショットに縮退し、呼び出し側がキャッシュしてよい形にする。
    @Test("非リポジトリでは空のスナップショットへ縮退する")
    func degradesToEmptySnapshotOutsideRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.statuses.isEmpty)
    }
}
