import AppKit
@testable import befold
@testable import BefoldCLI
import Foundation
import Testing

/// パス引数なしの CLI 起動(`befold --hidden-files` 等)でも、
/// セッション復元されるウィンドウへ表示オプションが適用されることを検証する。
/// SessionRestorer の存在確認とコントローラ生成パイプラインの双方を
/// MockedViewerWindowManager の InMemoryFileReader へ揃えているため実 FS を踏まない。
@Suite
@MainActor
struct SessionRestorerTests {
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")

    /// - Parameter resolveFileToOpen: openRootFallback の解決シームのスタブ。既定は本物の
    ///   DirectoryLister.resolveFileToOpen(実 FileManager でディレクトリ列挙する)だが、それだと
    ///   MockedViewerWindowManager の仮想パス("/repo" 等)を解決できず、フォールバックのテストが
    ///   書けない(実ディレクトリでないため常に nil になる)。フォールバックを検証するテストだけ
    ///   スタブを渡す。
    private func makeRestorer(
        _ fixture: MockedViewerWindowManager,
        resolveFileToOpen: @escaping (URL) -> URL? = { DirectoryLister.resolveFileToOpen(at: $0) },
        presentFileNotFound: @escaping (URL) -> Void = { _ in }
    ) -> SessionRestorer {
        SessionRestorer(
            sessionStore: fixture.sessionStore,
            windowManager: fixture.manager,
            fileReader: fixture.fileReader,
            resolveFileToOpen: resolveFileToOpen,
            presentFileNotFound: presentFileNotFound
        )
    }

    @Test("復元に渡した showHiddenFiles は復元直後に全体設定へ反映される")
    func hiddenFilesOptionAppliesOnRestore() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(showHiddenFiles: true))

        #expect(fixture.sidebarDisplayPreference.showHiddenFiles)
    }

    @Test("復元に渡した showLineNumbers は復元されるウィンドウへ適用される")
    func lineNumbersOptionAppliesToRestoredWindow() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(showLineNumbers: true))

        let controller = fixture.manager.controllers[file.normalizedPathKey]?.first
        #expect(controller?.store.showLineNumbers == true)
    }

    /// 復元経路は options をそのまま ViewerWindowManager へ渡す。フィールド単位の
    /// 手写しに戻ると、この経路だけ並び順の指定が落ちる形の欠落が起きうる。
    @Test("復元に渡した sortOrder は復元されるウィンドウへ適用される")
    func sortOrderOptionAppliesToRestoredWindow() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(sortOrder: .alphabetical))

        let controller = fixture.manager.controllers[file.normalizedPathKey]?.first
        #expect(controller?.fileListModel.sortOrder == .alphabetical)
    }

    @Test("オプション未指定時は従来どおり復元される(既定のフォルダー優先ソート)")
    func noOptionsPreservesDefaultRestoreBehavior() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession()

        #expect(!fixture.sidebarDisplayPreference.showHiddenFiles)
        #expect(fixture.manager.controllers[file.normalizedPathKey] != nil)
    }

    @Test("復元時に消えていたファイルはウィンドウを開かずセッション記録からも取り除かれる")
    func restoreLastSessionDropsMissingFilesFromRecord() {
        let missing = URL(fileURLWithPath: "/mock/gone.mmd")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(missing)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession()

        #expect(fixture.manager.controllers[file.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[missing.normalizedPathKey] == nil)
        let savedPaths = fixture.sessionStore.savedURLs().map(\.normalizedPathKey)
        #expect(!savedPaths.contains(missing.normalizedPathKey))
        #expect(savedPaths.contains(file.normalizedPathKey))
    }

    @Test("保存済みタブ構成が全て実在すればタブごと復元する")
    func openRepositoryRestoresSavedTabGroupWhenAllPathsExist() {
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let fileB = URL(fileURLWithPath: "/repo/b.md")
        let fixture = MockedViewerWindowManager(files: [fileA, fileB], prefix: "SessionRestorerOpenRepo")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [fileA.normalizedPathKey, fileB.normalizedPathKey], selectedPath: fileB.normalizedPathKey
        )

        restorer.openRepository(root: URL(fileURLWithPath: "/repo"), savedTabGroup: group)

        #expect(fixture.manager.controllers[fileA.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[fileB.normalizedPathKey] != nil)
    }

    @Test("保存済みタブ構成の一部が消えていれば残存パスだけで復元する")
    func openRepositoryFiltersMissingPathsFromSavedTabGroup() {
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let missing = URL(fileURLWithPath: "/repo/gone.md")
        let fixture = MockedViewerWindowManager(files: [fileA], prefix: "SessionRestorerOpenRepo")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [fileA.normalizedPathKey, missing.normalizedPathKey], selectedPath: missing.normalizedPathKey
        )

        restorer.openRepository(root: URL(fileURLWithPath: "/repo"), savedTabGroup: group)

        #expect(fixture.manager.controllers[fileA.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[missing.normalizedPathKey] == nil)
    }

    @Test("保存済みタブ構成が無ければルートフォルダ内の対応ファイルを解決して開く(ディレクトリ自体は開かない)")
    func openRepositoryFallsBackToFolderWhenNoSavedTabGroup() {
        let root = URL(fileURLWithPath: "/repo")
        let entry = URL(fileURLWithPath: "/repo/a.md")
        let fixture = MockedViewerWindowManager(files: [entry], prefix: "SessionRestorerOpenRepo")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture, resolveFileToOpen: { $0 == root ? entry : nil })

        restorer.openRepository(root: root, savedTabGroup: nil)

        #expect(fixture.manager.controllers[entry.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[root.normalizedPathKey] == nil)
    }

    @Test("保存済みタブ構成の全パスが消えていればルートフォルダ内の対応ファイルへフォールバックする(ディレクトリ自体は開かない)")
    func openRepositoryFallsBackToFolderWhenAllSavedPathsAreMissing() {
        let root = URL(fileURLWithPath: "/repo")
        let entry = URL(fileURLWithPath: "/repo/a.md")
        let fixture = MockedViewerWindowManager(files: [entry], prefix: "SessionRestorerOpenRepo")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture, resolveFileToOpen: { $0 == root ? entry : nil })
        let group = SessionLayout.TabGroup(
            paths: [URL(fileURLWithPath: "/repo/gone.md").normalizedPathKey], selectedPath: nil
        )

        restorer.openRepository(root: root, savedTabGroup: group)

        #expect(fixture.manager.controllers[entry.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[root.normalizedPathKey] == nil)
    }

    @Test("フォールバック解決が対応ファイル無しで nil を返せば、壊れたウィンドウを開かず FileNotFound で通知する")
    func openRepositoryFallbackNotifiesFileNotFoundWhenResolutionReturnsNil() {
        let root = URL(fileURLWithPath: "/repo")
        let fixture = MockedViewerWindowManager(files: [], prefix: "SessionRestorerOpenRepo")
        defer { fixture.closeAll() }
        var notifiedURLs: [URL] = []
        let restorer = makeRestorer(
            fixture, resolveFileToOpen: { _ in nil },
            presentFileNotFound: { notifiedURLs.append($0) }
        )

        restorer.openRepository(root: root, savedTabGroup: nil)

        #expect(fixture.manager.allControllers.isEmpty)
        #expect(notifiedURLs == [root])
    }

    /// 同じファイルを別々のタブグループで開くのは設計上許容しており、保存レイアウトにも
    /// そのまま記録される。2 件目の復元で既存ウィンドウを引き当てると、addTabbedWindow が
    /// その生きているウィンドウを前のグループから奪い、グループの構成が崩れる。
    @Test("同じパスが 2 つのタブグループにあっても、既存のウィンドウを奪わない")
    func restoreDoesNotStealWindowForPathInTwoGroups() {
        let shared = URL(fileURLWithPath: "/dup-repo/shared.md")
        let onlyA = URL(fileURLWithPath: "/dup-repo/only-a.md")
        let onlyB = URL(fileURLWithPath: "/dup-repo/only-b.md")
        let fixture = MockedViewerWindowManager(
            files: [shared, onlyA, onlyB], prefix: "SessionRestorerDuplicate"
        )
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        for url in [shared, onlyA, onlyB] {
            fixture.sessionStore.noteOpened(url)
        }
        fixture.sessionStore.saveLayout(
            SessionLayout(groups: [
                SessionLayout.TabGroup(
                    paths: [shared.normalizedPathKey, onlyA.normalizedPathKey],
                    selectedPath: shared.normalizedPathKey
                ),
                SessionLayout.TabGroup(
                    paths: [onlyB.normalizedPathKey, shared.normalizedPathKey],
                    selectedPath: onlyB.normalizedPathKey
                ),
            ])
        )

        restorer.captureSavedState()
        restorer.restoreLastSession()

        // 保存レイアウトが shared を 2 度含む以上、復元後も 2 つのウィンドウが要る。
        // 1 つしか無い状態は「2 件目が既存ウィンドウを奪った」ことを意味する。
        #expect(fixture.manager.controllers[shared.normalizedPathKey]?.count == 2)
    }

    /// 症状は「終了と再起動のたびに再発する」ため、1 往復で一致しても足りない。
    /// 保存 → 復元を 2 回繰り返しても、各グループのパス構成が保存時と同じであることを見る。
    @Test("重複パスを含む構成は、終了と再起動を 2 回繰り返しても保存時と一致する")
    func restoreKeepsTabGroupsStableAcrossTwoRestarts() {
        let shared = URL(fileURLWithPath: "/restart-repo/shared.md")
        let onlyA = URL(fileURLWithPath: "/restart-repo/only-a.md")
        let onlyB = URL(fileURLWithPath: "/restart-repo/only-b.md")
        let fixture = MockedViewerWindowManager(
            files: [shared, onlyA, onlyB], prefix: "SessionRestorerDuplicate"
        )
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        for url in [shared, onlyA, onlyB] {
            fixture.sessionStore.noteOpened(url)
        }
        let saved = SessionLayout(groups: [
            SessionLayout.TabGroup(
                paths: [shared.normalizedPathKey, onlyA.normalizedPathKey],
                selectedPath: shared.normalizedPathKey
            ),
            SessionLayout.TabGroup(
                paths: [onlyB.normalizedPathKey, shared.normalizedPathKey],
                selectedPath: onlyB.normalizedPathKey
            ),
        ])
        // 並び(前面から順)はウィンドウの重なりに左右されるため、グループの集合として比べる。
        let expected = Set(saved.groups.map { Set($0.paths) })
        // currentSessionLayout は NSApp のウィンドウを全て見るため、フルスイート実行では
        // 他テストのウィンドウも混ざる。このテストが開いた 3 パスに関係するグループだけを取る。
        let ownPaths = Set([shared, onlyA, onlyB].map(\.normalizedPathKey))
        func ownGroups(of layout: SessionLayout) -> Set<Set<String>> {
            Set(layout.groups.map { Set($0.paths) }.filter { !$0.isDisjoint(with: ownPaths) })
        }

        fixture.sessionStore.saveLayout(saved)
        restorer.captureSavedState()
        restorer.restoreLastSession()
        let afterFirst = restorer.currentSessionLayout()
        #expect(
            ownGroups(of: afterFirst) == expected,
            "1 回目の復元でタブ構成が保存時と違う: \(afterFirst.groups.map(\.paths))"
        )

        // 2 回目の起動。プロセスをまたいで運ばれるのは保存されたレイアウトと URL だけなので、
        // 別フィクスチャ(=別プロセス相当)へ 1 回目の保存結果を渡して同じことを繰り返す。
        let restarted = MockedViewerWindowManager(
            files: [shared, onlyA, onlyB], prefix: "SessionRestorerDuplicateRestart"
        )
        defer { restarted.closeAll() }
        let restartedRestorer = makeRestorer(restarted)
        for url in [shared, onlyA, onlyB] {
            restarted.sessionStore.noteOpened(url)
        }
        restarted.sessionStore.saveLayout(afterFirst)
        restartedRestorer.captureSavedState()
        restartedRestorer.restoreLastSession()

        let afterSecond = restartedRestorer.currentSessionLayout()
        #expect(
            ownGroups(of: afterSecond) == expected,
            "2 回目の復元でタブ構成が保存時と違う: \(afterSecond.groups.map(\.paths))"
        )
    }
}
