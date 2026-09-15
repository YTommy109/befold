@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// 文字入力の用件ごとに、初期値と文言のキーが揃っていることを View を起動せずに確かめる
/// (`SidebarEmptyReason` と同じ理由でキーを enum に出している)。
@Suite
struct BookmarkManagerPromptTests {
    private static let entry = BookmarkEntry(path: "/mock/docs/note.md", alias: "Weekly")
    private static let allPrompts: [BookmarkManagerPrompt] = [
        .alias(entry), .newFolder(parent: ["Work"]), .renameFolder(["Work", "Specs"]),
    ]

    @Test("初期値は別名・空・今のフォルダー名")
    func initialTextPerPrompt() {
        #expect(Self.allPrompts.map(\.initialText) == ["Weekly", "", "Specs"])
    }

    @Test("本文は別名ならパス、フォルダーなら置き場所")
    func messagePerPrompt() {
        #expect(Self.allPrompts.map(\.message) == ["/mock/docs/note.md", "Work", "Work"])
    }

    /// キーが `Localizable.xcstrings` に無いと `String(localized:)` はキー文字列をそのまま返す。
    /// 用件を足してキーを足し忘れると alert にキー名が出るだけで気づけないため、キーが訳を
    /// 持つことを確かめる。
    ///
    /// **`String(localized:)` の戻り値をキーと比較する形では判定できない**(実測:
    /// TASK-618)。`swift test` では String Catalog がコンパイルされないため、
    /// `String(localized:)` はキーが実在していても常にキー文字列を返す。一方
    /// `String(describing: key)` は `LocalizationValue(arguments: [], key: "...")` という
    /// 別形式を返すため、両者は常に不一致になり、キーが欠けていても検知できない。
    /// そこでカタログ(`LocalizableCatalog`)を直接読み、キーが実在し訳が空でないことを見る
    /// (`SidebarEmptyStateTests` と同じ判定)。
    @Test("すべての用件に、解決できる見出し・プレースホルダ・適用ボタンの文言がある")
    func resolvesEveryKey() throws {
        let catalog = try LocalizableCatalog.load(bundle: .l10n)

        for prompt in Self.allPrompts {
            for localizationKey in [prompt.titleKey, prompt.placeholderKey, prompt.applyKey] {
                let key = localizationKey.rawKeyForTesting
                #expect(catalog[key]?["ja"]?.isEmpty == false, "キー \(key) に ja の訳がありません")
                #expect(catalog[key]?["en"]?.isEmpty == false, "キー \(key) に en の訳がありません")
            }
        }
    }
}
