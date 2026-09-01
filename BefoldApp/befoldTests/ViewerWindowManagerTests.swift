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
        fixture.manager.sessionSync.viewerWindow(controller, didRenameFrom: old, to: renamed)

        #expect(fixture.recentDocumentsStore.recentURLs().map(\.path) == [renamed.normalizedPathKey])
    }

    @Test("window(forPath:) が開いたウィンドウを返す")
    func windowForPathReturnsOpenWindow() throws {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)

        let window = try #require(fixture.manager.window(forPath: file.normalizedPathKey))
        #expect(ViewerTabGrouping.viewerPath(of: window) == file.normalizedPathKey)
    }

    @Test("switchFile で管理辞書のキーが付け替わりセッション記録が更新される")
    func switchFileUpdatesControllerKeyAndSession() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file1)
        let controller = try #require(fixture.manager.controllers[file1.normalizedPathKey]?.first)
        fixture.manager.sessionSync.viewerWindow(controller, didSwitchFileFrom: file1, to: file2)

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

    /// **どのファイルを開いても、出発点は最後に調整した 1 個(TASK-583)。**
    /// かつてはファイル自身の保存値が最優先で、開いた時点でそれを書き戻していたため、
    /// 一度開いたファイルは自分の古い寸法に固定され、あとから調整した値が届かなかった。
    @Test("開く寸法は、最後にユーザーが調整したフレームで決まる")
    func openViewerUsesLastUserAdjustedFrame() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        fixture.windowFrame.recordUserAdjustedFrame("200 200 900 700 0 0 1920 1080")

        let controller = fixture.manager.openViewer(for: file)

        #expect(controller?.window?.frame.size == NSSize(width: 900, height: 700))
    }

    /// 粒度がアプリ全体であることを、破れたら落ちる形で固定する。ファイル単位の記憶が
    /// 復活すると、この期待（別ファイルでも同じ寸法）が崩れる。
    @Test("別のファイルを開いても同じ寸法から始まる")
    func openViewerUsesTheSameFrameForEveryFile() {
        let first = URL(fileURLWithPath: "/mock/first.mmd")
        let second = URL(fileURLWithPath: "/mock/second.mmd")
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        fixture.windowFrame.recordUserAdjustedFrame("50 50 700 500 0 0 1920 1080")

        let firstController = fixture.manager.openViewer(for: first)
        let secondController = fixture.manager.openViewer(for: second)

        #expect(firstController?.window?.frame.size == NSSize(width: 700, height: 500))
        #expect(secondController?.window?.frame.size == NSSize(width: 700, height: 500))
    }

    /// 開いただけでは何も書かない。書き戻していたことが、グローバル値が届かなくなった原因。
    @Test("ファイルを開いても、調整していない寸法は記録されない")
    func openViewerDoesNotRecordFrameOnItsOwn() {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)

        #expect(fixture.windowFrame.lastUserAdjustedFrameDescriptor == nil)
    }
}
