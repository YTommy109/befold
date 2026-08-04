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

    @Test("パス無しCLI起動の --hidden-files は復元直後に全体設定へ反映される")
    func hiddenFilesOptionAppliesOnRestore() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        defer { fixture.closeAll() }
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(showHiddenFiles: true))

        #expect(fixture.sidebarDisplayPreference.showHiddenFiles)
    }

    @Test("パス無しCLI起動の --line-numbers は復元されるウィンドウへ適用される")
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
    @Test("パス無しCLI起動の --sort alphabetical は復元されるウィンドウへ適用される")
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
}
