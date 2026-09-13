@testable import befold
import BefoldKit
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
    /// 用件を足してキーを足し忘れると alert にキー名が出るだけで気づけないため、解決結果がキーと
    /// 異なることまで確かめる。
    @Test("すべての用件に、解決できる見出し・プレースホルダ・適用ボタンの文言がある")
    func resolvesEveryKey() {
        for prompt in Self.allPrompts {
            for key in [prompt.titleKey, prompt.placeholderKey, prompt.applyKey] {
                let text = String(localized: key, bundle: .l10n)
                #expect(!text.isEmpty)
                #expect(text != String(describing: key))
            }
        }
    }
}
