@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 表示中ファイルの再読込(= 保存)がサイドバーの git 状態を取り直す配線を検証する。
/// 作業ツリーの編集は `.git/index` を動かさないため index 監視では拾えず、
/// この配線が「編集保存 → unstaged バッジ」の唯一の契機になる(TASK-186.2)。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowControllerGitStatusTests {
    /// 呼ばれた回数を数え、決め打ちのスナップショットを返す reader。実 git を起動しない。
    private final class StubReader: GitStatusReading, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private let snapshot: GitStatusSnapshot

        init(snapshot: GitStatusSnapshot) {
            self.snapshot = snapshot
        }

        func indexFingerprint(forRepositoryAt _: URL) -> Date? {
            nil
        }

        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls
        }

        func status(forRepositoryAt _: URL) -> GitStatusSnapshot? {
            lock.lock()
            calls += 1
            lock.unlock()
            return snapshot
        }
    }

    @Test("表示中ファイルの再読込で git 状態を取り直す")
    func reloadingContentRefreshesGitStatuses() async {
        let root = URL(fileURLWithPath: "/mock")
        let file = root.appendingPathComponent("a.mmd")
        let statuses = [file.path: GitFileStatus(indexChange: nil, worktreeChange: .modified)]
        let reader = StubReader(
            snapshot: GitStatusSnapshot(statuses: statuses, indexFingerprint: nil, indexURL: nil)
        )
        let fixture = ViewerWindowControllerFixture(
            file: file,
            prefix: "ViewerWindowControllerGitStatusTests",
            gitStatusStore: GitStatusStore(reader: reader, resolveRepositoryRoot: { _ in root })
        )
        defer { fixture.close() }
        let controller = fixture.controller
        await controller.sidebar.pendingGitStatusTask?.value
        let callsBeforeReload = reader.callCount

        // ViewerStore がファイル変更を検知して再読込したときに呼ばれるクロージャ。
        // ここを直接叩くことで、実 FileWatcher とデバウンスを待たずに配線だけを確かめる。
        controller.store.onContentReloaded?()
        await controller.sidebar.pendingGitStatusTask?.value

        #expect(reader.callCount > callsBeforeReload)
        #expect(controller.sidebar.fileListModel.gitStatuses == statuses)
    }
}
