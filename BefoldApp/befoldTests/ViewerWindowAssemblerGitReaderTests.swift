@testable import befold
import BefoldKit
import Foundation
import Testing

/// フェイクのルート解決が返すリポジトリルート（実在しなくてよい）。
/// Sendable なクロージャから参照するため、MainActor 隔離される型の外に置く。
private let fakeRepositoryRoot = URL(fileURLWithPath: "/repos/befold")

/// リポジトリを開けなかったことにする reader。実 git を起動しない。
private struct UnopenableGitStatusReader: GitStatusReading {
    func status(forRepositoryAt _: URL) -> GitStatusSnapshot? {
        nil
    }

    func indexFingerprint(forRepositoryAt _: URL) -> Date? {
        nil
    }
}

/// サイドバーへ渡す git reader が statusStore まで配線されていることの回帰。
///
/// 以前はフィーチャーゲートの ON/OFF 両方向を見ていた（TASK-419）が、ゲート撤去（TASK-187）
/// により残るのは「常に store を引く」側だけ。`makeSidebarGitReader` の配線を測るのは
/// このテストが唯一なので、ゲートと一緒に消さずに縮小して残している。
@Suite
@MainActor
struct ViewerWindowAssemblerGitReaderTests {
    @Test("git 状態の取得は statusStore まで届く")
    func sidebarGitReaderReachesStatusStore() async {
        let reader = ViewerWindowAssembler.makeSidebarGitReader(
            fileIndex: DisabledGitFileIndex(),
            statusStore: GitStatusStore(
                reader: UnopenableGitStatusReader(),
                resolveRepositoryRoot: { _ in fakeRepositoryRoot }
            )
        )

        let result = await reader.statuses(forDirectoryAt: fakeRepositoryRoot, policy: .always)
        // store まで届いていればルートが載る（届かなければ .empty のまま）。
        #expect(result.repositoryRoot == fakeRepositoryRoot)
        #expect(result != .empty)
    }
}
