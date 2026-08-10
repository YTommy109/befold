@testable import befold
import Foundation
import Testing

/// 一覧が 0 件になった理由の出し分け(`SidebarEmptyState.reason(activeGitChangeFilter:filterText:)`)。
///
/// View から切り出した純粋関数なので、SwiftUI を起動せずに 4 分岐すべてを押さえられる。
/// 文言そのものではなく **理由の判定** を守るのがこのテストの役目。
/// 「対応ファイルがありません」へ落ちる条件は「絞り込みが 1 つも効いていないとき」だけ、
/// という不変条件が破れたら落ちる(TASK-287 / TASK-405)。
struct SidebarEmptyStateTests {
    private let status = SidebarGitStatus(repositoryRootKey: "/repo", statuses: [:])

    @Test("絞り込みが効いていなければ「対応ファイルなし」")
    func reportsNoSupportedFilesWithoutAnyFilter() {
        #expect(SidebarEmptyState.reason(activeGitChangeFilter: nil, filterText: "") == .noSupportedFiles)
    }

    @Test("git 絞り込みだけが効いていれば「変更ファイルなし」")
    func reportsGitChangeFilterOnly() {
        #expect(SidebarEmptyState.reason(activeGitChangeFilter: status, filterText: "") == .gitChangeFilter)
    }

    /// TASK-405 の本体。名前フィルターで消えたときに「対応ファイルなし」へ落ちると、
    /// 開ける文書で満たされたフォルダーでも読み込みに失敗したように読める。
    @Test("名前フィルターだけが効いていれば「一致なし」")
    func reportsNameFilterOnly() {
        #expect(SidebarEmptyState.reason(activeGitChangeFilter: nil, filterText: "*.md") == .nameFilter)
    }

    /// 両方効いているときに片方だけの文言を出すと、もう片方を解除しても一覧が
    /// 戻らず「解除したのに変わらない」になる。
    @Test("両方効いていれば両方を挙げる理由になる")
    func reportsBothFilters() {
        #expect(
            SidebarEmptyState.reason(activeGitChangeFilter: status, filterText: "*.md")
                == .gitChangeAndNameFilter
        )
    }

    /// 空白だけのフィルター文字列は `FileListFilter.apply` が絞り込みに使わない
    /// (`filterText.isEmpty` が false でも `WildcardMatcher` へ渡る)ため、
    /// 理由の判定も `apply` と同じ「空文字かどうか」で揃える。
    @Test("フィルター文字列が空でなければ、内容によらず名前フィルターが効いていると見なす")
    func treatsAnyNonEmptyFilterTextAsActive() {
        #expect(SidebarEmptyState.reason(activeGitChangeFilter: nil, filterText: " ") == .nameFilter)
    }

    private static let allReasons: [SidebarEmptyReason] = [
        .noSupportedFiles, .gitChangeFilter, .nameFilter, .gitChangeAndNameFilter,
    ]

    /// キーが `Localizable.xcstrings` に無いと、`String(localized:)` はキー文字列を
    /// そのまま返す。理由を足してキーを足し忘れると、画面に `sidebar.empty.bothFilters` と
    /// 出るだけで気づけないため、解決結果がキーと異なることまで確かめる。
    @Test("すべての理由に、解決できる見出し文言がある")
    func resolvesTitleForEveryReason() {
        for reason in Self.allReasons {
            let title = String(localized: reason.titleKey, bundle: .l10n)
            #expect(!title.isEmpty)
            #expect(title != String(describing: reason.titleKey))
        }
    }

    /// 絞り込みで空になった 3 通りには、解除の手立てを伝える説明が要る。
    /// 「対応ファイルなし」だけは説明の代わりにフォルダー名を添えるため nil。
    @Test("絞り込みで空になった理由には、解決できる説明文言がある")
    func resolvesDescriptionForFilteredReasons() throws {
        #expect(SidebarEmptyReason.noSupportedFiles.descriptionKey == nil)

        for reason in Self.allReasons where reason != .noSupportedFiles {
            let key = try #require(reason.descriptionKey)
            let description = String(localized: key, bundle: .l10n)
            #expect(!description.isEmpty)
            #expect(description != String(describing: key))
        }
    }

    /// 理由ごとに違う文言が出ることまで確かめる。同じキーを 2 つの理由へ割り当てると、
    /// 判定は正しいのに画面は区別されない(AC #2 が実質満たされない)状態になる。
    @Test("理由ごとに異なる見出し文言が割り当てられている")
    func assignsDistinctTitlePerReason() {
        let titles = Self.allReasons.map { String(localized: $0.titleKey, bundle: .l10n) }

        #expect(Set(titles).count == Self.allReasons.count)
    }
}
