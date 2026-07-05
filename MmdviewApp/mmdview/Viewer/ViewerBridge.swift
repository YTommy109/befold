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

    /// 表示中ファイルの切り替え時などに、保存済み倍率を注入し直して即時反映する
    /// スクリプト。viewer.html 側は _mmdInitZoom() が _mmdInitialZoom を読んで適用する。
    static func applyZoomScript(_ zoom: Double) -> String {
        initialZoomScript(zoom) + " _mmdInitZoom();"
    }

    /// ロード時にシステム本文フォントサイズ(pt)を注入するスクリプト。
    /// viewer.html 側は _mmdInitFontSize() が読んで CSS 変数へ反映する。
    static func systemFontSizeScript(_ size: Double) -> String {
        "window._mmdSystemFontSize = \(size);"
    }

    /// render(content, type[, lang]) 呼び出しを組み立てる。
    /// content は JSONEncoder でエスケープし、JS インジェクションを防ぐ。
    /// .code の場合は第 3 引数で highlight.js の言語名を、
    /// .csv の場合は区切り文字（","／"\t"）を渡す
    /// (いずれも FileType の対応表由来の固定文字列のみで、ユーザー入力は混入しない)。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    static func renderScript(content: String, fileType: FileType) -> String? {
        guard let jsonData = try? JSONEncoder().encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        if let language = fileType.codeLanguage {
            return "render(\(jsonString), '\(fileType.jsValue)', '\(language)')"
        }
        if let delimiter = fileType.csvDelimiter {
            let escaped = delimiter == "\t" ? "\\t" : delimiter
            return "render(\(jsonString), '\(fileType.jsValue)', '\(escaped)')"
        }
        return "render(\(jsonString), '\(fileType.jsValue)')"
    }

    /// レンダリング表示とソース表示の切り替えモード。
    enum ViewMode: String {
        case rendered
        case source
    }

    /// setViewMode(mode) 呼び出しを組み立てる。
    static func viewModeScript(_ mode: ViewMode) -> String {
        "setViewMode('\(mode.rawValue)')"
    }
}
