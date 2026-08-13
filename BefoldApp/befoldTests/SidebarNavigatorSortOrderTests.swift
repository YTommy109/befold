@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 並び順の粒度(TASK-474)を守らせるテスト。
///
/// 決めた形は「窓が生きている間は窓ごとのライブ値、保存値は次に窓を開くときの既定値」
/// (ADR 0002 の「文書の状態」)。この形が破れる典型は 2 つあり、どちらもここで落ちる。
///
/// - 変更を全窓へ配ってしまう → `liveSortOrderStaysPerWindow` が落ちる
/// - 生きている窓が保存値を読み直す → 同上(他窓の操作が後から効いてしまう)
@Suite
@MainActor
struct SidebarNavigatorSortOrderTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private func makePreference() -> SidebarDisplayPreference {
        SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorSortOrderTests")
        )
    }

    private func makeNavigator(
        preference: SidebarDisplayPreference, sortOrder: befold.SortOrder? = nil
    ) -> SidebarNavigator {
        SidebarNavigator(
            currentDirectory: Self.home,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: preference,
            sortOrder: sortOrder,
            directoryLister: { _, _, _ in DirectoryListing(rootChildren: []) },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
    }

    @Test("新しい窓は保存された既定値の並び順で始まる")
    func newWindowStartsFromStoredDefault() {
        let preference = makePreference()
        preference.sortOrder = .alphabetical

        #expect(makeNavigator(preference: preference).fileListModel.sortOrder == .alphabetical)
    }

    @Test("setSortOrder はこの窓のライブ値と保存された既定値の両方を更新する")
    func setSortOrderUpdatesLiveValueAndStoredDefault() {
        let preference = makePreference()
        let navigator = makeNavigator(preference: preference)

        navigator.setSortOrder(.alphabetical)

        #expect(navigator.fileListModel.sortOrder == .alphabetical)
        #expect(preference.sortOrder == .alphabetical)
    }

    /// 保存されるのは「次に開く窓の既定値」なので、後から開いた窓だけが追随する。
    @Test("並び順を変えた後に開いた窓はその並び順で始まる")
    func laterWindowPicksUpTheNewDefault() {
        let preference = makePreference()
        makeNavigator(preference: preference).setSortOrder(.alphabetical)

        #expect(makeNavigator(preference: preference).fileListModel.sortOrder == .alphabetical)
    }

    /// **粒度の担保**: 並び順は窓ごとのライブ値なので、片方の窓での変更が
    /// 既に開いている別の窓へ波及してはならない。全窓へ配る実装にすると落ちる。
    @Test("既に開いている別の窓の並び順は変わらない")
    func liveSortOrderStaysPerWindow() {
        let preference = makePreference()
        let first = makeNavigator(preference: preference)
        let second = makeNavigator(preference: preference)

        first.setSortOrder(.alphabetical)

        #expect(first.fileListModel.sortOrder == .alphabetical)
        #expect(second.fileListModel.sortOrder == .foldersFirst)
    }

    /// CLI の `--sort` はその起動限りの窓単位の上書きなので、既定値を書き換えない。
    @Test("初期並び順の明示指定は保存された既定値を書き換えない")
    func explicitInitialSortOrderDoesNotWriteDefault() {
        let preference = makePreference()

        let navigator = makeNavigator(preference: preference, sortOrder: .alphabetical)

        #expect(navigator.fileListModel.sortOrder == .alphabetical)
        #expect(preference.sortOrder == .foldersFirst)
    }
}
