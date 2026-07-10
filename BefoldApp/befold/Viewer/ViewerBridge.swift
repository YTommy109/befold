import Foundation

/// viewer.html 内の JS と Swift の間のブリッジ契約(関数名・メッセージ名・グローバル変数)を集約する。
/// ここの文字列を変更する場合は viewer.html 側の定義とあわせて変更すること
/// (整合性は ViewerBridgeTests がソースを読んで検証する)。
enum ViewerBridge {
    /// JS 側で全体ズーム倍率が変わったときに postMessage されるメッセージハンドラ名。
    static let zoomChangedMessageName = "zoomChanged"

    /// cmd+click でリンクやパス参照がアクティベートされたときに postMessage されるメッセージハンドラ名。
    /// payload: { href: String, isExternal: Bool, newWindow: Bool }
    static let referenceActivatedMessageName = "referenceActivated"

    static let zoomInScript = "_mmdZoomIn()"
    static let zoomOutScript = "_mmdZoomOut()"
    static let zoomResetScript = "_mmdZoomReset()"

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
    /// 第 3 引数(lang)は FileType.renderLangArgument が返す固定文字列
    /// (.code の言語名 / .csv の区切り文字 / .image の MIME タイプ)のみで、
    /// ユーザー入力は混入しない。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    static func renderScript(content: String, fileType: FileType) -> String? {
        guard let jsonData = try? JSONEncoder().encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        guard let lang = fileType.renderLangArgument else {
            return "render(\(jsonString), '\(fileType.jsValue)')"
        }
        let escaped = lang == "\t" ? "\\t" : lang
        return "render(\(jsonString), '\(fileType.jsValue)', '\(escaped)')"
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

    /// setLineNumbers(show) 呼び出しを組み立てる。
    static func lineNumbersScript(_ show: Bool) -> String {
        "setLineNumbers(\(show))"
    }

    /// 検索バーを開く(未オープンなら表示してフォーカス)スクリプト。
    static let openFindScript = "_mmdOpenFind()"

    /// JS 側で検索トグル(大文字小文字区別・単語マッチ・正規表現)が変わったときに
    /// postMessage されるメッセージハンドラ名。
    static let findOptionsChangedMessageName = "findOptionsChanged"

    /// 検索の3トグルの状態。
    struct FindOptions: Equatable {
        var caseSensitive: Bool
        var wholeWord: Bool
        var useRegex: Bool
    }

    /// ロード時に検索トグルの保存済み状態を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdInitialFindOptions を読んで適用する。
    static func initialFindOptionsScript(_ options: FindOptions) -> String {
        "window._mmdInitialFindOptions = { caseSensitive: \(options.caseSensitive), " +
            "wholeWord: \(options.wholeWord), useRegex: \(options.useRegex) };"
    }
}
