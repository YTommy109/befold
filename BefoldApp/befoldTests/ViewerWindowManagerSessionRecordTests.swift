import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 同一ファイルを複数ウィンドウで開いた状態でのセッション記録の増減を検証する。
/// ViewerWindowManager.controllers は [正規化パス: [コントローラ]] の 1 対多なので、
/// 窓を 1 枚閉じた/切り替えただけでセッション集合から消してはいけない(TASK-412)。
/// 本体の ViewerWindowManagerTests から分けているのは type_body_length を超えるため。
@Suite
@MainActor
struct ViewerWindowManagerSessionRecordTests {
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")
    private let file1 = URL(fileURLWithPath: "/mock/first.mmd")
    private let file2 = URL(fileURLWithPath: "/mock/second.mmd")

    /// 閉じるたびに無条件で noteClosed を呼ぶ実装だと、まだ表示している窓が残っているのに
    /// セッション集合とアクティブ記録から消える。参照が残る間は消えないことを固定する。
    @Test("同じファイルの窓が他に残っていれば、1 枚閉じてもセッション記録は消えない")
    func closingOneOfTwoWindowsForSameFileKeepsSessionEntry() throws {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: file, disposition: .newWindow)
        fixture.sessionStore.noteActivated(file, kind: .viewer)
        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 2)

        let first = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        first.close()

        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 1)
        #expect(fixture.sessionStore.savedURLs().map(\.normalizedPathKey) == [file.normalizedPathKey])
        // アクティブ記録も、まだ開いている窓の分として残す。
        #expect(fixture.sessionStore.savedActivePath() == file.normalizedPathKey)
    }

    @Test("同じファイルの最後の 1 枚を閉じたときはセッション記録から消える")
    func closingLastWindowForSameFileNotesClosed() throws {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: file, disposition: .newWindow)
        fixture.sessionStore.noteActivated(file, kind: .viewer)

        for controller in try #require(fixture.manager.controllers[file.normalizedPathKey]) {
            controller.close()
        }

        #expect(fixture.manager.controllers.isEmpty)
        #expect(fixture.sessionStore.savedURLs().isEmpty)
        #expect(fixture.sessionStore.savedActivePath() == nil)
    }

    /// スライド窓は復元の対象外なので、開いても切り替えてもキーになってもセッションへ書かない
    /// (TASK-612)。書いてしまうと `SessionRestorer` が savedURLs 経由で通常窓として復元する。
    @Test("スライド窓だけで開いても、セッション記録にもアクティブ記録にも入らない")
    func slideOnlyWindowDoesNotEnterSessionRecord() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }

        let slide = try #require(fixture.manager.openViewer(for: file1, disposition: .slide))
        fixture.manager.sessionSync.viewerWindowDidBecomeKey(slide)
        fixture.manager.sessionSync.viewerWindow(slide, didSwitchFileFrom: file1, to: file2)

        #expect(fixture.sessionStore.savedURLs().isEmpty)
        #expect(fixture.sessionStore.savedActivePath() == nil)
    }

    /// 通常窓を閉じてスライド窓だけが残った状態は「復元するものが無い」なので閉じたことにする。
    /// 窓の数(controllers の有無)で判定していると、スライド窓が残る間ずっと記録が残る。
    @Test("通常窓を閉じてスライド窓だけが残れば、セッション記録から消える")
    func closingViewerWindowWhileSlideRemainsNotesClosed() throws {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        let viewer = try #require(fixture.manager.openViewer(for: file))
        fixture.manager.openViewer(for: file, disposition: .slide)
        #expect(fixture.sessionStore.savedURLs().map(\.normalizedPathKey) == [file.normalizedPathKey])

        viewer.close()

        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 1)
        #expect(fixture.sessionStore.savedURLs().isEmpty)
    }

    @Test("スライド窓を閉じても、同じファイルの通常窓のセッション記録は消えない")
    func closingSlideWindowKeepsViewerSessionEntry() throws {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let slide = try #require(fixture.manager.openViewer(for: file, disposition: .slide))

        slide.close()

        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 1)
        #expect(fixture.sessionStore.savedURLs().map(\.normalizedPathKey) == [file.normalizedPathKey])
    }

    /// スライド窓がキーになっても、直前にキーだった通常窓のアクティブ記録を上書きしない
    /// (TASK-616)。上書きされると savedURLs / レイアウトに無いパスがキー窓の指定になり、
    /// 再起動時に本来キーになるべき通常窓がキーにならない。
    /// 終了時の書き手(`AppDelegate.applicationShouldTerminate`)はヘッドレスで実行できないが、
    /// そちらも同じ `SessionStore.noteActivated(_:kind:)` を通り、種別は必須引数なので
    /// 渡し忘れはコンパイルエラーになる。
    @Test("スライド窓がキーになっても、直前の通常窓のアクティブ記録は変わらない")
    func slideWindowBecomingKeyKeepsTheViewerActivePath() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }
        let viewer = try #require(fixture.manager.openViewer(for: file1))
        fixture.manager.sessionSync.viewerWindowDidBecomeKey(viewer)
        let slide = try #require(fixture.manager.openViewer(for: file2, disposition: .slide))

        fixture.manager.sessionSync.viewerWindowDidBecomeKey(slide)

        #expect(fixture.sessionStore.savedActivePath() == file1.normalizedPathKey)
    }

    /// 復元時にキーにする窓の引き当て(TASK-616)。起動時の CLI 要求でスライド窓が先に
    /// 開いていると、`controllers` の先頭はスライド窓になる。絞らないとそれがキーにされる。
    @Test("同じパスでスライド窓が先に開いていても、window(forPath:) は通常窓を返す")
    func windowForPathSkipsSlideWindows() throws {
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        let slide = try #require(fixture.manager.openViewer(for: file, disposition: .slide))
        let viewer = try #require(fixture.manager.openViewer(for: file, disposition: .newWindow))
        #expect(fixture.manager.controllers[file.normalizedPathKey]?.first === slide)

        #expect(fixture.manager.window(forPath: file.normalizedPathKey) === viewer.window)
    }

    /// remapController も close と同型。窓 B が別ファイルへ切り替わったとき、
    /// 窓 A がまだ表示している旧パスをセッション集合から落としてはいけない。
    @Test("同じファイルの窓が他に残っていれば、片方のファイル切替でも旧パスは消えない")
    func switchingOneOfTwoWindowsForSameFileKeepsSessionEntry() throws {
        let fixture = MockedViewerWindowManager(files: [file1, file2])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file1)
        fixture.manager.openViewer(for: file1, disposition: .newWindow)
        let first = try #require(fixture.manager.controllers[file1.normalizedPathKey]?.first)

        first.switchFile(to: file2)

        #expect(fixture.manager.controllers[file1.normalizedPathKey]?.count == 1)
        let savedPaths = fixture.sessionStore.savedURLs().map(\.normalizedPathKey)
        #expect(savedPaths.contains(file1.normalizedPathKey))
        #expect(savedPaths.contains(file2.normalizedPathKey))
    }
}
