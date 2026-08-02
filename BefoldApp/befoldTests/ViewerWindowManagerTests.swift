import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ViewerWindowManager の辞書管理・セッション記録・サイドバー開閉/フレームの初期状態解決を検証する。
/// コントローラ生成は MockedViewerWindowManager 経由で InMemoryFileReader + MockFileWatcher +
/// 空のディレクトリ列挙に差し替えているため実 FS を踏まない。
/// サイドバー entries の実列挙が対象のテストは ViewerWindowManagerIntegrationTests に残している。
@Suite
@MainActor
struct ViewerWindowManagerTests {
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")
    private let file1 = URL(fileURLWithPath: "/mock/first.mmd")
    private let file2 = URL(fileURLWithPath: "/mock/second.mmd")

    @Test("可視なのにアクティブ Space に居ないウィンドウだけが救出対象と判定される")
    func isDetachedFromSpaceRequiresVisibleAndOffActiveSpace() {
        #expect(ViewerWindowManager.isDetachedFromSpace(isVisible: true, isOnActiveSpace: false))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: true, isOnActiveSpace: true))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: false, isOnActiveSpace: false))
        #expect(!ViewerWindowManager.isDetachedFromSpace(isVisible: false, isOnActiveSpace: true))
    }

    /// コントローラ側の既定は「git を使わない索引」なので、注入を書き忘れるとパス参照の
    /// リンク化が黙って効かなくなる。生成経路が共有インスタンスを渡していることを固定する。
    @Test("生成したウィンドウには共有の git 索引が注入される")
    func openViewerInjectsSharedGitFileIndex() {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file1)
        fixture.manager.openViewer(for: file2)

        // 2 ウィンドウ分の先読みが同じ 1 個の索引に届いている。
        #expect(fixture.gitFileIndex.warmedPaths.map(\.path) == [file1.path, file2.path])
    }

    @Test("同じファイルを二度開いてもウィンドウは 1 つに集約される")
    func openViewerReusesControllerForSamePath() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: file)

        #expect(fixture.manager.controllers.count == 1)
    }

    @Test("単一ファイル指定では従来通りウィンドウは1つだけ開く(回帰確認)")
    func singleCLITargetOpensExactlyOneWindow() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)

        #expect(fixture.manager.controllers.count == 1)
    }

    @Test("ウィンドウクローズで管理辞書から除去されセッション記録も閉じられる")
    func closingWindowRemovesControllerAndNotesClosed() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)
        #expect(fixture.sessionStore.savedURLs().map(\.normalizedPathKey) == [file.normalizedPathKey])

        fixture.manager.controllers[file.normalizedPathKey]?.first?.close()

        #expect(fixture.manager.controllers.isEmpty)
        #expect(fixture.sessionStore.savedURLs().isEmpty)
    }

    @Test("ファイルを開くと Open Recent 履歴に記録される")
    func openViewerRecordsRecentDocument() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)

        #expect(fixture.recentDocumentsStore.recentURLs().map(\.path) == [file.normalizedPathKey])
    }

    @Test("rename が Open Recent 履歴に反映される")
    func renameUpdatesRecentDocuments() throws {
        let old = URL(fileURLWithPath: "/mock/old.mmd")
        let renamed = URL(fileURLWithPath: "/mock/new.mmd")
        let fixture = MockedViewerWindowManager(files: [old, renamed])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: old)

        let controller = try #require(fixture.manager.controllers[old.normalizedPathKey]?.first)
        fixture.manager.viewerWindow(controller, didRenameFrom: old, to: renamed)

        #expect(fixture.recentDocumentsStore.recentURLs().map(\.path) == [renamed.normalizedPathKey])
    }

    @Test("window(forPath:) が開いたウィンドウを返す")
    func windowForPathReturnsOpenWindow() throws {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)

        let window = try #require(fixture.manager.window(forPath: file.normalizedPathKey))
        #expect(fixture.manager.viewerPath(of: window) == file.normalizedPathKey)
    }

    @Test("switchFile で管理辞書のキーが付け替わりセッション記録が更新される")
    func switchFileUpdatesControllerKeyAndSession() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file1)
        let controller = try #require(fixture.manager.controllers[file1.normalizedPathKey]?.first)
        fixture.manager.viewerWindow(controller, didSwitchFileFrom: file1, to: file2)

        #expect(fixture.manager.controllers[file1.normalizedPathKey] == nil)
        #expect(fixture.manager.controllers[file2.normalizedPathKey] != nil)
        let savedPaths = fixture.sessionStore.savedURLs().map(\.normalizedPathKey)
        #expect(savedPaths.contains(file2.normalizedPathKey))
        #expect(!savedPaths.contains(file1.normalizedPathKey))
    }

    @Test("別ウィンドウで開いているファイルへも、アクティブウィンドウ側で切り替わる")
    func switchToFileOpenInAnotherWindowSwitchesActiveWindow() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file1)
        fixture.manager.openViewer(for: file2)
        let first = try #require(fixture.manager.controllers[file1.normalizedPathKey]?.first)
        let second = try #require(fixture.manager.controllers[file2.normalizedPathKey]?.first)

        // file2 が別ウィンドウ(second)で開いていても、操作中の first がそのまま file2 へ切り替わる。
        // 「1ファイル1ウィンドウ」制約は撤廃したため、file2 は 2 ウィンドウに映る。
        first.switchFile(to: file2)

        #expect(first.fileURL == file2)
        // file2 のキーに first と second の両方が登録される(前面化・切替中止はしない)。
        let file2Controllers = try #require(fixture.manager.controllers[file2.normalizedPathKey])
        #expect(file2Controllers.count == 2)
        #expect(file2Controllers.contains { $0 === first })
        #expect(file2Controllers.contains { $0 === second })
        // 元の file1 のキーからは first が外れる。
        #expect(fixture.manager.controllers[file1.normalizedPathKey] == nil)
    }

    @Test("performFileSwitch は別ウィンドウで開いていても切替を完了する")
    func performFileSwitchSwitchesEvenWhenOpenElsewhere() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file1)
        fixture.manager.openViewer(for: file2)
        let first = try #require(fixture.manager.controllers[file1.normalizedPathKey]?.first)

        let outcome = first.performFileSwitch(to: file2)

        guard case .switched = outcome else {
            Issue.record("別ウィンドウで開いていても切替は完了(.switched)すべき: \(outcome)")
            return
        }
        #expect(first.fileURL == file2)
    }

    @Test("履歴で戻る先が別ウィンドウで開かれていても、前面化せず自ウィンドウで戻る")
    func historyNavigationToFileOpenElsewhereSwitchesWithoutFocusing() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file1)
        let first = try #require(fixture.manager.controllers[file1.normalizedPathKey]?.first)
        // file1 -> file2 の切替で file1 が履歴に残る。
        first.switchFile(to: file2)
        // 戻る先(file1)を別ウィンドウで開いてから戻ろうとする。
        fixture.manager.openViewer(for: file1)
        let second = try #require(
            fixture.manager.controllers[file1.normalizedPathKey]?.first { $0 !== first }
        )
        first.window?.makeKeyAndOrderFront(nil)

        first.navigateHistory(by: -1)

        // 自ウィンドウ(first)が file1 へ戻り、別ウィンドウ(second)は前面化しない。
        #expect(first.fileURL.normalizedPathKey == file1.normalizedPathKey)
        #expect(second.window?.isKeyWindow == false)
    }

    @Test("新規ファイルを開くと、記録がなければ既定(閉じた状態)がサイドバー状態として記録される")
    func openViewerPersistsDefaultClosedSidebarStateForNewFile() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == true)
    }

    @Test("既に保存済みのサイドバー状態があるファイルを開いても保存値は上書きされない")
    func openViewerKeepsOwnSavedSidebarState() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        fixture.perFileState.sidebar.setCollapsed(false, for: file)

        fixture.manager.openViewer(for: file)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
    }

    @Test("初めて開くファイルは直近アクティブだったウィンドウのサイドバー状態を引き継ぐ")
    func openViewerInheritsLastActiveWindowSidebarState() {
        let activeFile = URL(fileURLWithPath: "/mock/active.mmd")
        let newFile = URL(fileURLWithPath: "/mock/new.mmd")
        let fixture = MockedViewerWindowManager(files: [activeFile, newFile])
        defer { fixture.closeAll() }
        fixture.perFileState.sidebar.setCollapsed(false, for: activeFile)
        fixture.sessionStore.noteActivated(activeFile)

        fixture.manager.openViewer(for: newFile)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: newFile) == false)
    }

    @Test("forceSidebarVisible は保存済み・引き継ぎ値より優先され、結果も記録される")
    func openViewerForceSidebarVisibleOverridesResolvedDefault() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file, forceSidebarVisible: true)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
    }

    @Test("既に保存済みのウィンドウフレームがあるファイルを開いても保存値は上書きされない")
    func openViewerKeepsOwnSavedWindowFrame() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        fixture.perFileState.windowFrame.setFrameDescriptor("200 200 900 700 0 0 1920 1080", for: file)

        fixture.manager.openViewer(for: file)

        #expect(
            fixture.perFileState.windowFrame.frameDescriptor(for: file) == "200 200 900 700 0 0 1920 1080"
        )
    }

    @Test("初めて開くファイルは直近アクティブだったウィンドウのフレームを引き継ぐ")
    func openViewerInheritsLastActiveWindowFrame() {
        let activeFile = URL(fileURLWithPath: "/mock/active.mmd")
        let newFile = URL(fileURLWithPath: "/mock/new.mmd")
        let fixture = MockedViewerWindowManager(files: [activeFile, newFile])
        defer { fixture.closeAll() }
        fixture.perFileState.windowFrame.setFrameDescriptor("50 50 700 500 0 0 1920 1080", for: activeFile)
        fixture.sessionStore.noteActivated(activeFile)

        fixture.manager.openViewer(for: newFile)

        #expect(
            fixture.perFileState.windowFrame.frameDescriptor(for: newFile) == "50 50 700 500 0 0 1920 1080"
        )
    }

    @Test("記録が何もない新規ファイルはウィンドウフレームを記録しない(既定のカスケード配置に任せる)")
    func openViewerLeavesWindowFrameUnsetWhenNothingToInherit() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)

        #expect(fixture.perFileState.windowFrame.frameDescriptor(for: file) == nil)
    }

    // MARK: - makeTabGroup(タブ構成スナップショットの組み立て)

    @Test("ビューアパスを持つタブが1枚も無ければタブグループを作らない")
    func makeTabGroupReturnsNilWhenNoViewerTabs() {
        let group = ViewerWindowManager.makeTabGroup(
            tabWindows: ["a", "b"], selectedWindow: "a", viewerPath: { _ in nil }
        )

        #expect(group == nil)
    }

    /// タブがすべてビューアの場合の入力と期待値。
    struct TabGroupCase: Sendable, CustomTestStringConvertible {
        let name: String
        let tabWindows: [String]
        let selectedWindow: String
        let expectedPaths: [String]
        let expectedSelectedPath: String
        var testDescription: String {
            name
        }
    }

    /// 単独ウィンドウは「全タブがビューア」の縮退ケースなので同じ表で回す。
    private nonisolated static let tabGroupCases: [TabGroupCase] = [
        TabGroupCase(
            name: "単独ウィンドウ",
            tabWindows: ["/a.mmd"], selectedWindow: "/a.mmd",
            expectedPaths: ["/a.mmd"], expectedSelectedPath: "/a.mmd"
        ),
        TabGroupCase(
            name: "先頭が選択されている3タブ",
            tabWindows: ["/a.mmd", "/b.mmd", "/c.mmd"], selectedWindow: "/a.mmd",
            expectedPaths: ["/a.mmd", "/b.mmd", "/c.mmd"], expectedSelectedPath: "/a.mmd"
        ),
        TabGroupCase(
            name: "中央が選択されている3タブ",
            tabWindows: ["/a.mmd", "/b.mmd", "/c.mmd"], selectedWindow: "/b.mmd",
            expectedPaths: ["/a.mmd", "/b.mmd", "/c.mmd"], expectedSelectedPath: "/b.mmd"
        ),
    ]

    @Test("タブ順は保たれ、選択タブのパスが selectedPath になる", arguments: tabGroupCases)
    func makeTabGroupKeepsTabOrderAndSelection(_ testCase: TabGroupCase) throws {
        let group = try #require(
            ViewerWindowManager.makeTabGroup(
                tabWindows: testCase.tabWindows, selectedWindow: testCase.selectedWindow, viewerPath: { $0 }
            )
        )

        #expect(group.paths == testCase.expectedPaths)
        #expect(group.selectedPath == testCase.expectedSelectedPath)
    }

    @Test("ビューアでないタブは除外され、選択タブがビューアでなければ selectedPath は nil になる")
    func makeTabGroupSkipsNonViewerTabs() throws {
        let group = try #require(
            ViewerWindowManager.makeTabGroup(
                tabWindows: ["/a.mmd", "other", "/c.mmd"], selectedWindow: "other",
                viewerPath: { $0.hasPrefix("/") ? $0 : nil }
            )
        )

        #expect(group.paths == ["/a.mmd", "/c.mmd"])
        #expect(group.selectedPath == nil)
    }
}
