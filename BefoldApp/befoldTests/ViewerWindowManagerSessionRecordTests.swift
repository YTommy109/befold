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
        fixture.sessionStore.noteActivated(file)
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
        fixture.sessionStore.noteActivated(file)

        for controller in try #require(fixture.manager.controllers[file.normalizedPathKey]) {
            controller.close()
        }

        #expect(fixture.manager.controllers.isEmpty)
        #expect(fixture.sessionStore.savedURLs().isEmpty)
        #expect(fixture.sessionStore.savedActivePath() == nil)
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
