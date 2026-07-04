import Foundation

/// viewer.html 内の JS と Swift の間のブリッジ契約(関数名・メッセージ名・グローバル変数)を集約する。
/// ここの文字列を変更する場合は viewer.html 側の定義とあわせて変更すること
/// (整合性は ViewerBridgeTests がソースを読んで検証する)。
enum ViewerBridge {
    /// JS 側で全体ズーム倍率が変わったときに postMessage されるメッセージハンドラ名。
    static let zoomChangedMessageName = "zoomChanged"

    static let zoomInScript = "_mmdZoomIn()"
    static let zoomOutScript = "_mmdZoomOut()"
    static let zoomResetScript = "_mmdZoomReset()"
    static let showDeletedBannerScript = "showDeletedBanner()"

    /// ロード時にファイル毎の初期倍率を注入するスクリプト。
    static func initialZoomScript(_ zoom: Double) -> String {
        "window._mmdInitialZoom = \(zoom);"
    }

    /// ロード時にシステム本文フォントサイズ(pt)を注入するスクリプト。
    /// viewer.html 側は _mmdInitFontSize() が読んで CSS 変数へ反映する。
    static func systemFontSizeScript(_ size: Double) -> String {
        "window._mmdSystemFontSize = \(size);"
    }

    /// render(content, type[, lang]) 呼び出しを組み立てる。
    /// content は JSONEncoder でエスケープし、JS インジェクションを防ぐ。
    /// .code の場合のみ第 3 引数で highlight.js の言語名を渡す
    /// (言語名は FileType の対応表由来の固定文字列のみで、ユーザー入力は混入しない)。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    static func renderScript(content: String, fileType: FileType) -> String? {
        guard let jsonData = try? JSONEncoder().encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        if let language = fileType.codeLanguage {
            return "render(\(jsonString), '\(fileType.jsValue)', '\(language)')"
        }
        return "render(\(jsonString), '\(fileType.jsValue)')"
    }
}
