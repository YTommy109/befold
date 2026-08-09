import Foundation

/// 状態でラベルが入れ替わるビューアコマンドの文言。
///
/// 同じトグルの文言をメニュー(validateMenuItem)とツールバー(ツールチップ・
/// アクセシビリティ説明)の双方が出すため、対になる 2 つの文言をここに集約する。
/// 片方だけ差し替えるとメニューとツールバーで表記が食い違う。
enum ViewerCommandTitles {
    /// View > 行番号表示。表示中なら「隠す」、非表示なら「表示する」。
    static func lineNumbers(isShown: Bool) -> String {
        isShown
            ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
            : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
    }

    /// View > ブックマーク。登録済みなら「解除」、未登録なら「追加」。
    static func bookmark(isBookmarked: Bool) -> String {
        isBookmarked
            ? String(localized: "menu.view.removeBookmark", bundle: .l10n)
            : String(localized: "menu.view.addBookmark", bundle: .l10n)
    }

    /// モード切替セグメントの差分。現在のレイアウト（インライン / 左右分割）まで伝える。
    /// セグメントは選択中に再クリックするとレイアウトが切り替わるため、
    /// 「いまどちらか」を説明とツールチップで示す必要がある。
    static func diffMode(isSideBySide: Bool) -> String {
        isSideBySide
            ? String(localized: "toolbar.mode.diff.sideBySide", bundle: .l10n)
            : String(localized: "toolbar.mode.diff.inline", bundle: .l10n)
    }

    /// View > ソース表示。ソース表示中なら「レンダリング表示へ」、それ以外なら「ソース表示へ」。
    static func sourceView(isSourceMode: Bool) -> String {
        isSourceMode
            ? String(localized: "menu.view.showRendered", bundle: .l10n)
            : String(localized: "menu.view.toggleSource", bundle: .l10n)
    }
}
