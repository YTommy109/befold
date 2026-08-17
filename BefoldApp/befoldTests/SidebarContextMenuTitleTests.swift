@testable import befold
import Foundation
import Testing

/// コンテキストメニューの「リンクをコピーする」文言が origin のホストに追随すること。
///
/// 固定文言に戻ると、別のホストを使っているリポジトリで嘘の名前を見せることになる
/// （逆に、解決できないときにホスト名を出すのも同じ嘘になる）。
///
/// 文言そのものは引数で渡す。`swift test` では `Localizable.xcstrings` の解決が効かず
/// キー名が返るため、localized な文字列を内側で引くとバンドル解決を測ることになる
/// （en / ja の登録有無は `/l10n-check` が担保する）。
struct SidebarContextMenuTitleTests {
    private let format = "Copy %@ Link"
    private let neutralTitle = "Copy Remote Link"

    @Test("解決できたホストの名前が文言に入る", arguments: RemoteForge.allCases)
    func includesForgeDisplayName(forge: RemoteForge) {
        let title = SidebarContextMenu.copyRemoteLinkTitle(
            for: forge, format: format, neutralTitle: neutralTitle
        )

        #expect(title == "Copy \(forge.displayName) Link")
    }

    @Test("解決できないときはどのホスト名も入らない")
    func omitsForgeNameWhenUnresolved() {
        let title = SidebarContextMenu.copyRemoteLinkTitle(
            for: nil, format: format, neutralTitle: neutralTitle
        )

        #expect(title == neutralTitle)
        for forge in RemoteForge.allCases {
            #expect(!title.contains(forge.displayName), "\(forge.displayName) が中立の文言に混ざっている")
        }
    }
}
