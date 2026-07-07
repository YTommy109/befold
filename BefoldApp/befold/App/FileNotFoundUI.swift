import AppKit

/// 「File Not Found」アラートの生成と表示(GUI 層・自動テスト対象外)。
///
/// 表示に関する差異はすべてこの型が一手に担い、呼び出し側は選択肢を持たない:
///   - 表示パスの正規化: URL を受け取り normalizedPathKey に揃える。各経路で
///     normalizedPathKey / path を選び分けると経路間で表示がズレる。
///   - 表示形式(シート / アプリモーダル): 親ウィンドウの有無だけで決める。
///     呼び出し側は自分が持つウィンドウ(無ければ nil)を渡すだけでよい。
@MainActor
enum FileNotFoundUI {
    /// File Not Found アラートを表示する。
    /// `window` があればそこにシート表示し、無ければアプリモーダルで表示する。
    static func present(url: URL, over window: NSWindow?) {
        let alert = makeAlert(for: url)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func makeAlert(for url: URL) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "alert.fileNotFound.message",
            defaultValue: "File Not Found",
            bundle: .l10n
        )
        // 経路によりシンボリックリンクの解決状態が異なる(/tmp と /private/tmp 等)ため、
        // 表示パスは normalizedPathKey に揃えて経路間で一致させる。
        alert.informativeText = url.normalizedPathKey
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        return alert
    }
}
