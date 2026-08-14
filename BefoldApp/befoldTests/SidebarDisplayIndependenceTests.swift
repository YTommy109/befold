@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// サイドバー表示 4 値の粒度(TASK-480)を守らせるテスト。
///
/// 決めた形は ADR 0002 の**窓の状態**——「窓が生きている間はその窓のライブ値、
/// アプリ全体の保存値は次に窓を開くときの初期値」。この形が破れる典型は 3 つあり、
/// いずれもここで落ちる。
///
/// - 変更を全窓へ配ってしまう → `liveValuesStayPerWindow` が落ちる
/// - 生きている窓が保存値を読み直す → 同上(他窓の操作が後から効いてしまう)
/// - 変更を保存値へ書き戻さない → `changeIsRecordedAsTheDefaultForNewWindows` が落ちる
///
/// 並び順だけを見るテストは `SidebarNavigatorSortOrderTests` に先にあり、
/// ここは残る 3 値を同じ形で固定する(TASK-480 で 4 値を同じ粒度へ揃えたため)。
@Suite
@MainActor
struct SidebarDisplayIndependenceTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// 4 値それぞれの「変更」と、変更後に期待される値の読み出し。
    private struct DisplayValue: CustomTestStringConvertible {
        let name: String
        let change: SidebarDisplayChange
        /// 窓のライブ値。
        let live: @MainActor (SidebarNavigator) -> Bool
        /// 保存された既定値。
        let stored: @MainActor (SidebarDisplayDefaults) -> Bool
        var testDescription: String {
            name
        }
    }

    private nonisolated static let values: [DisplayValue] = [
        DisplayValue(
            name: "不可視ファイル表示", change: .toggleHiddenFiles,
            live: { $0.fileListModel.showHiddenFiles },
            stored: { $0.settings.showHiddenFiles }
        ),
        DisplayValue(
            name: "変更ファイルのみ表示", change: .toggleChangedFilesOnly,
            live: { $0.fileListModel.showChangedFilesOnly },
            stored: { $0.settings.showChangedFilesOnly }
        ),
        DisplayValue(
            name: "表示形式(ツリー)", change: .toggleLayoutMode,
            live: { $0.fileListModel.layoutMode == .tree },
            stored: { $0.settings.layoutMode == .tree }
        ),
        DisplayValue(
            name: "並び順(アルファベット順)", change: .setSortOrder(.alphabetical),
            live: { $0.fileListModel.sortOrder == .alphabetical },
            stored: { $0.settings.sortOrder == .alphabetical }
        ),
    ]

    private func makeDefaults(_ suffix: String) -> SidebarDisplayDefaults {
        SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "SidebarDisplayIndependenceTests-\(suffix)")
        )
    }

    private func makeNavigator(defaults: SidebarDisplayDefaults) -> SidebarNavigator {
        SidebarNavigator(
            currentDirectory: Self.home,
            entries: [],
            selection: nil,
            displayDefaults: defaults,
            directoryLister: { _, _, _ in DirectoryListing(rootChildren: []) },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
    }

    /// **同じ既定値ストアを共有する 2 窓**を作る。共有しているのが「次に開く窓の初期値」
    /// でしかないことが要点で、片方の操作がもう片方へ届いてはならない。
    ///
    /// もう一方の窓は**一覧を取り直してから**確かめる。取り直しの契機で保存値を読み直す形
    /// (TASK-480 以前の `syncDisplayPreferences`)へ戻すと、ここで初めて他窓の操作が届く。
    /// 取り直さずに読むだけでは、その回帰を素通しする。
    @Test("一方の窓で変えた表示設定は、一覧を取り直したもう一方の窓にも届かない", arguments: values)
    private func liveValuesStayPerWindow(_ value: DisplayValue) async {
        let defaults = makeDefaults(value.change.testKey)
        let changed = makeNavigator(defaults: defaults)
        let untouched = makeNavigator(defaults: defaults)
        let host = SidebarNavigatorStubHost(currentFileURL: Self.home.appendingPathComponent("a.md"))
        untouched.attach(to: host)
        defer { withExtendedLifetime(host) {} }

        changed.applyDisplayChange(value.change)
        untouched.refreshFileList()
        await untouched.awaitSettled()

        #expect(value.live(changed))
        #expect(!value.live(untouched))
    }

    @Test("変えた値は保存され、その後に開いた窓の初期値になる", arguments: values)
    private func changeIsRecordedAsTheDefaultForNewWindows(_ value: DisplayValue) {
        let defaults = makeDefaults("record-\(value.change.testKey)")
        let changed = makeNavigator(defaults: defaults)

        changed.applyDisplayChange(value.change)

        #expect(value.stored(defaults))
        #expect(value.live(makeNavigator(defaults: defaults)))
    }
}

private extension SidebarDisplayChange {
    /// 一時ディレクトリ名に使う ASCII 識別子(ケースごとに一意)。
    var testKey: String {
        switch self {
        case .toggleHiddenFiles: "hidden"
        case .toggleChangedFilesOnly: "changed"
        case .toggleLayoutMode: "layout"
        case .setSortOrder: "sort"
        }
    }
}
