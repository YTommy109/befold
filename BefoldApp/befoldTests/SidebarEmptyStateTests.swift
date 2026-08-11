@testable import befold
import Foundation
import Testing

/// 一覧が 0 件になった理由の出し分け(`SidebarEmptyState.reason(for:)`)。
///
/// View から切り出した純粋関数なので、SwiftUI を起動せずに全分岐を押さえられる。
/// 文言そのものではなく **理由の判定** を守るのがこのテストの役目。
/// 「対応ファイルがありません」へ落ちる条件は「絞り込みが 1 つも効いておらず、
/// 列挙にも成功しているとき」だけ、という不変条件が破れたら落ちる
/// (TASK-287 / TASK-405 / TASK-410)。
struct SidebarEmptyStateTests {
    private let status = SidebarGitStatus(repositoryRootKey: "/repo", statuses: [:])

    /// 理由の入力。既定は「読めて、絞り込みも効いていない」。
    private func context(
        gitChangeFilter: SidebarGitStatus? = nil,
        filterText: String = "",
        didFailEnumeration: Bool = false
    ) -> SidebarEmptyContext {
        SidebarEmptyContext(
            activeGitChangeFilter: gitChangeFilter,
            filterText: filterText,
            directoryName: "docs",
            didFailEnumeration: didFailEnumeration
        )
    }

    @Test("絞り込みが効いていなければ「対応ファイルなし」")
    func reportsNoSupportedFilesWithoutAnyFilter() {
        #expect(SidebarEmptyState.reason(for: context()) == .noSupportedFiles)
    }

    @Test("git 絞り込みだけが効いていれば「変更ファイルなし」")
    func reportsGitChangeFilterOnly() {
        #expect(SidebarEmptyState.reason(for: context(gitChangeFilter: status)) == .gitChangeFilter)
    }

    /// TASK-405 の本体。名前フィルターで消えたときに「対応ファイルなし」へ落ちると、
    /// 開ける文書で満たされたフォルダーでも読み込みに失敗したように読める。
    @Test("名前フィルターだけが効いていれば「一致なし」")
    func reportsNameFilterOnly() {
        #expect(SidebarEmptyState.reason(for: context(filterText: "*.md")) == .nameFilter)
    }

    /// 両方効いているときに片方だけの文言を出すと、もう片方を解除しても一覧が
    /// 戻らず「解除したのに変わらない」になる。
    @Test("両方効いていれば両方を挙げる理由になる")
    func reportsBothFilters() {
        let both = context(gitChangeFilter: status, filterText: "*.md")

        #expect(SidebarEmptyState.reason(for: both) == .gitChangeAndNameFilter)
    }

    /// 空白だけのフィルター文字列は `FileListFilter.apply` が絞り込みに使わない
    /// (`filterText.isEmpty` が false でも `WildcardMatcher` へ渡る)ため、
    /// 理由の判定も `apply` と同じ「空文字かどうか」で揃える。
    @Test("フィルター文字列が空でなければ、内容によらず名前フィルターが効いていると見なす")
    func treatsAnyNonEmptyFilterTextAsActive() {
        #expect(SidebarEmptyState.reason(for: context(filterText: " ")) == .nameFilter)
    }

    /// TASK-410 の本体。読めなかったフォルダーを「対応ファイルがありません」と
    /// 言い切ると、権限の無いフォルダーが空のフォルダーと同じ見た目になる。
    @Test("列挙に失敗していれば「読み取れません」")
    func reportsEnumerationFailure() {
        #expect(SidebarEmptyState.reason(for: context(didFailEnumeration: true)) == .enumerationFailed)
    }

    /// 失敗は絞り込みより先に確定させる。絞り込みの文言は「解除すれば見えます」を
    /// 含むため、読めなかったフォルダーへ出すと解除しても何も起きない案内になる。
    @Test("列挙に失敗していれば、絞り込みが効いていても失敗の理由が優先される")
    func enumerationFailureWinsOverFilters() {
        let filtered = context(
            gitChangeFilter: status, filterText: "*.md", didFailEnumeration: true
        )

        #expect(SidebarEmptyState.reason(for: filtered) == .enumerationFailed)
    }

    private static let allReasons: [SidebarEmptyReason] = [
        .enumerationFailed, .noSupportedFiles, .gitChangeFilter, .nameFilter, .gitChangeAndNameFilter,
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

    /// 絞り込みで空になった 3 通りと列挙失敗には、次の一手を伝える説明が要る。
    /// 「対応ファイルなし」だけは説明の代わりにフォルダー名を添えるため nil。
    @Test("説明文言を持つ理由には、解決できる説明文言がある")
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

    /// 失敗の見出しは、ツリー展開の失敗行(FileListEntryRow の help)と同じキーを使う。
    /// 同じ事象に別の言い回しを作ると、片方だけ直されて画面ごとに説明が食い違う。
    @Test("列挙失敗の見出しは、ツリーの失敗行と同じ文言キーを使う")
    func sharesFailureWordingWithTreeRow() {
        // FileListEntryRow が使うキーのリテラルと同じ文言に解決されることを見る。
        #expect(String(localized: SidebarEmptyReason.enumerationFailed.titleKey, bundle: .l10n)
            == String(localized: "folder.enumerationFailed", bundle: .l10n))
    }
}
