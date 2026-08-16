import SwiftUI

/// Quick Open パネル内のキー操作が起こす動作。
///
/// 以前は `QuickOpenView` の `.onKeyPress` / `.onSubmit` にキーと動作の対応が直接
/// 書かれていて、Help の一覧に載せる情報源が無かった(TASK-503)。`SidebarKeyAction` と
/// 同じく、キー → 動作の対応だけを純粋関数へ切り出し、ビューは結果を実行する側に徹する。
enum QuickOpenKeyAction: Equatable {
    /// 候補の選択を 1 つ動かす(負なら上へ)。
    case moveSelection(offset: Int)
    /// 入力中のパスを補完する。
    case completePath
    /// 選択中の候補を開く。
    case commit
    /// パネルを閉じる。
    case dismiss

    /// 対応が無いキーには nil を返し、ビューは `.ignored` としてシステムへ委ねる。
    static func action(for key: KeyEquivalent) -> QuickOpenKeyAction? {
        switch key {
        case .upArrow: .moveSelection(offset: -1)
        case .downArrow: .moveSelection(offset: 1)
        case .tab: .completePath
        case .return: .commit
        case .escape: .dismiss
        default: nil
        }
    }
}

/// Quick Open のキー操作を Help > キーボードショートカット に載せるための一覧。
///
/// 情報源は `QuickOpenKeyAction.action(for:)` のままで、ここは表示に要る対応づけだけを持つ。
/// ずれは `QuickOpenKeyActionTests` が双方向(健全性・完全性)に縛る。
enum QuickOpenShortcutCatalog {
    struct Item {
        let keys: [KeyEquivalent]
        let titleKey: String
    }

    /// 見出しのローカライズキー。訳の有無は LocalizationTests が検証する。
    static let sectionTitleKey = "shortcuts.section.quickOpen"

    static let items: [Item] = [
        Item(keys: [.downArrow, .upArrow], titleKey: "shortcuts.quickOpen.moveSelection"),
        Item(keys: [.tab], titleKey: "shortcuts.quickOpen.completePath"),
        Item(keys: [.return], titleKey: "shortcuts.quickOpen.commit"),
        Item(keys: [.escape], titleKey: "shortcuts.quickOpen.dismiss"),
    ]

    static var section: ShortcutSection {
        ShortcutSection(
            title: String(localized: .init(sectionTitleKey), bundle: .l10n),
            entries: items.map {
                ShortcutEntry(
                    title: String(localized: .init($0.titleKey), bundle: .l10n),
                    keys: $0.keys.map { ShortcutKey(key: $0) }
                )
            }
        )
    }
}
