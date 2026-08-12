import AppKit

/// クリップボードへの書き込みを 1 箇所に集める。
///
/// サイドバーの右クリックメニュー（`FileListView`）と本文のパス参照メニュー
/// （`ReferenceMenuPresenter`）が同じ「コピー」項目を持つため、`clearContents()` の
/// 呼び忘れのような差がメニューごとに生まれないようここへ寄せる。
enum Pasteboard {
    /// 文字列を書き込む（パス・ファイル名のコピー）。
    static func writeString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// ファイル参照を書き込む（Finder へ貼り付けるとファイルそのものが渡る）。
    static func writeFileReference(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}
