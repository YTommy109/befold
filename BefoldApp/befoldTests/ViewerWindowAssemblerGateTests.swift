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

/// サイドバーの git ステータス系ゲートの露出点が、ゲート値を引数で受けて
/// ON / OFF の両方向で正しく振る舞うことを検証する（TASK-419）。
///
/// 実ビルドではゲートが片側に固定される（stable の OFF はローカルの Release ビルドでも
/// 確認できない）ため、両分岐は注入点で押さえる。
@Suite
@MainActor
struct ViewerWindowAssemblerGateTests {
    private func makeStatusStore() -> GitStatusStore {
        GitStatusStore(
            reader: UnopenableGitStatusReader(),
            resolveRepositoryRoot: { _ in fakeRepositoryRoot }
        )
    }

    /// ゲート OFF では状態取得だけが落ちる（ルート解決はゲート対象外なので動く）。
    @Test("git 状態の取得はゲートの両方向で正しい", arguments: [true, false])
    func sidebarGitReaderFollowsGateInBothDirections(isGitStatusAvailable: Bool) async {
        let reader = ViewerWindowAssembler.makeSidebarGitReader(
            fileIndex: DisabledGitFileIndex(),
            statusStore: makeStatusStore(),
            isGitStatusAvailable: isGitStatusAvailable
        )

        let result = await reader.statuses(forDirectoryAt: fakeRepositoryRoot, policy: .always)
        // 有効なら store まで届いてルートが載る。無効なら store を引かず空のまま。
        #expect(result.repositoryRoot == (isGitStatusAvailable ? fakeRepositoryRoot : nil))
        #expect((result != .empty) == isGitStatusAvailable)
    }

    /// ゲート OFF ではサイドバーヘッダーの「変更されたファイルのみ表示」ボタンが出ない。
    @Test("変更ファイル絞り込みのトグルはゲートの両方向で正しい", arguments: [true, false])
    func changedFilesOnlyToggleFollowsGateInBothDirections(isChangedFilesOnlyAvailable: Bool) {
        let controller = ViewerWindowControllerFixture(
            file: URL(fileURLWithPath: "/mock/a.mmd"),
            prefix: "ViewerWindowAssemblerGateTests"
        ).controller
        defer { controller.close() }

        let toggle = ViewerWindowAssembler.makeChangedFilesOnlyToggle(
            for: controller, isChangedFilesOnlyAvailable: isChangedFilesOnlyAvailable
        )

        #expect((toggle != nil) == isChangedFilesOnlyAvailable)
    }

    /// ゲート OFF ではサイドバーヘッダーの表示形式ボタンが出ない。
    /// 「変更されたファイルのみ表示」と同型の露出点にしている(TASK-473)。
    @Test("表示形式のトグルはゲートの両方向で正しい", arguments: [true, false])
    func sidebarTreeLayoutToggleFollowsGateInBothDirections(isTreeLayoutAvailable: Bool) {
        let controller = ViewerWindowControllerFixture(
            file: URL(fileURLWithPath: "/mock/a.mmd"),
            prefix: "ViewerWindowAssemblerGateTests"
        ).controller
        defer { controller.close() }

        let toggle = ViewerWindowAssembler.makeSidebarTreeLayoutToggle(
            for: controller, isTreeLayoutAvailable: isTreeLayoutAvailable
        )

        #expect((toggle != nil) == isTreeLayoutAvailable)
    }
}
