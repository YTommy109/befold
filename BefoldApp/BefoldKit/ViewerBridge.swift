import Foundation

/// viewer.html 内の JS と Swift の間のブリッジ契約(関数名・メッセージ名・グローバル変数)を集約する。
/// ここの文字列を変更する場合は viewer.html 側の定義とあわせて変更すること
/// (整合性は ViewerBridgeTests がソースを読んで検証する)。
public enum ViewerBridge {
    /// JS 側でスクロール位置が変わったときに postMessage されるメッセージハンドラ名。
    /// payload: { position: Double, mode: String }
    public static let scrollPositionChangedMessageName = "scrollPositionChanged"

    /// JS 側で全体ズーム倍率が変わったときに postMessage されるメッセージハンドラ名。
    public static let zoomChangedMessageName = "zoomChanged"

    /// リンクやパス参照がクリックされたときに postMessage されるメッセージハンドラ名。
    /// 無修飾クリックで同一ウィンドウ遷移、cmd+click で新規ウィンドウ遷移。
    /// payload: { href: String, newWindow: Bool }
    public static let referenceActivatedMessageName = "referenceActivated"

    public static let zoomInScript = "_mmdZoomIn()"
    public static let zoomOutScript = "_mmdZoomOut()"
    public static let zoomResetScript = "_mmdZoomReset()"

    /// ロード時にファイル毎の初期倍率を注入するスクリプト。
    public static func initialZoomScript(_ zoom: Double) -> String {
        "window._mmdInitialZoom = \(zoom);"
    }

    /// 表示中ファイルの切り替え時などに、保存済み倍率を注入し直して即時反映する
    /// スクリプト。viewer.html 側は _mmdInitZoom() が _mmdInitialZoom を読んで適用する。
    public static func applyZoomScript(_ zoom: Double) -> String {
        initialZoomScript(zoom) + " _mmdInitZoom();"
    }

    /// ロード時にシステム本文フォントサイズ(pt)を注入するスクリプト。
    /// viewer.html 側は _mmdInitFontSize() が読んで CSS 変数へ反映する。
    public static func systemFontSizeScript(_ size: Double) -> String {
        "window._mmdSystemFontSize = \(size);"
    }

    /// render(content, type[, lang]) 呼び出しを組み立てる。
    /// content は JSONEncoder でエスケープし、JS インジェクションを防ぐ。
    /// 第 3 引数(lang)は FileType.renderLangArgument が返す固定文字列
    /// (.code の言語名 / .csv の区切り文字 / .image の MIME タイプ)のみで、
    /// ユーザー入力は混入しない。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    public static func renderScript(content: String, fileType: FileType) -> String? {
        guard let jsonData = try? JSONEncoder().encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        guard let lang = fileType.renderLangArgument else {
            return "render(\(jsonString), '\(fileType.jsValue)')"
        }
        let escaped = lang == "\t" ? "\\t" : lang
        return "render(\(jsonString), '\(fileType.jsValue)', '\(escaped)')"
    }

    /// render() 呼び出しの直前に評価し、次に復元すべきスクロール位置(scrollTop)を
    /// JS 側へ注入するスクリプト。viewer.html 側は _mmdSetRestoreScroll() が受け取った
    /// 値を保持し、続く render() の末尾でその位置を復元する。
    /// position が非有限値(NaN/Infinity)の場合は不正な JS リテラルになるため 0 にフォールバックする。
    public static func restoreScrollPositionScript(_ position: Double) -> String {
        "_mmdSetRestoreScroll(\(position.isFinite ? position : 0))"
    }

    /// 現在のスクロール位置(scrollTop)を同期的に取得するスクリプト。ファイル/モード
    /// 切替直前に、退場側の正確な位置を明示的なキー(旧 URL・旧モード)へ保存するために使う
    /// (詳細は ViewerWindowController.saveCurrentScrollPosition 参照)。
    public static let currentScrollPositionScript = "(function() { var el = _mmdScrollTarget(); return el ? el.scrollTop : 0; })()"

    /// レンダリング表示とソース表示の切り替えモード。
    public enum ViewMode: String, Sendable {
        case rendered
        case source
    }

    /// setViewMode(mode) 呼び出しを組み立てる。
    public static func viewModeScript(_ mode: ViewMode) -> String {
        "setViewMode('\(mode.rawValue)')"
    }

    /// setLineNumbers(show) 呼び出しを組み立てる。
    public static func lineNumbersScript(_ show: Bool) -> String {
        "setLineNumbers(\(show))"
    }

    /// _mmdSetTruncated(isTruncated) 呼び出しを組み立てる。
    public static func truncatedScript(_ isTruncated: Bool) -> String {
        "_mmdSetTruncated(\(isTruncated))"
    }

    /// _mmdSetTruncated(isTruncated, lineCount) 呼び出しを組み立てる。
    public static func truncatedScript(_ isTruncated: Bool, lineCount: Int) -> String {
        "_mmdSetTruncated(\(isTruncated), \(lineCount))"
    }

    /// JS 側「続きを読み込む」ボタン押下時に postMessage されるメッセージハンドラ名。
    public static let loadMoreLinesMessageName = "loadMoreLines"

    /// appendChunk(content, type[, lang]) 呼び出しを組み立てる。
    /// content は JSONEncoder でエスケープし、JS インジェクションを防ぐ。
    /// エンコードに失敗した場合は nil(呼び出し側は何もしない)。
    public static func appendChunkScript(chunk: String, fileType: FileType) -> String? {
        guard let jsonData = try? JSONEncoder().encode(chunk),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        guard let lang = fileType.renderLangArgument else {
            return "appendChunk(\(jsonString), '\(fileType.jsValue)')"
        }
        let escaped = lang == "\t" ? "\\t" : lang
        return "appendChunk(\(jsonString), '\(fileType.jsValue)', '\(escaped)')"
    }

    /// ロード時にバナーのローカライズ済み文字列を JS 側へ注入するスクリプト。
    /// viewer.html 側は _mmdSetTruncated() が window._mmdBannerStrings を読んで表示する。
    public static func bannerStringsScript(bundle: Bundle = .main) -> String {
        let strings: [String: String] = [
            "showing": String(localized: "banner.showing", bundle: bundle),
            "loadMore": String(localized: "banner.loadMore", bundle: bundle),
        ]
        guard let jsonData = try? JSONEncoder().encode(strings),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return "window._mmdBannerStrings = {};"
        }
        return "window._mmdBannerStrings = \(jsonString);"
    }

    /// 検索バーを開く(未オープンなら表示してフォーカス)スクリプト。
    public static let openFindScript = "_mmdOpenFind()"

    /// 次のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    public static let findNextScript = "_mmdFindNextIfOpen()"

    /// 前のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    public static let findPrevScript = "_mmdFindPrevIfOpen()"

    /// JS 側で検索トグル(大文字小文字区別・単語マッチ・正規表現)が変わったときに
    /// postMessage されるメッセージハンドラ名。
    public static let findOptionsChangedMessageName = "findOptionsChanged"

    /// 検索の3トグルの状態。
    public struct FindOptions: Equatable {
        public var caseSensitive: Bool
        public var wholeWord: Bool
        public var useRegex: Bool

        public init(caseSensitive: Bool, wholeWord: Bool, useRegex: Bool) {
            self.caseSensitive = caseSensitive
            self.wholeWord = wholeWord
            self.useRegex = useRegex
        }
    }

    /// ロード時に検索トグルの保存済み状態を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdInitialFindOptions を読んで適用する。
    public static func initialFindOptionsScript(_ options: FindOptions) -> String {
        "window._mmdInitialFindOptions = { caseSensitive: \(options.caseSensitive), " +
            "wholeWord: \(options.wholeWord), useRegex: \(options.useRegex) };"
    }

    /// ロード時に検索バーのローカライズ済み文字列を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdFindStrings を読んで各要素に適用する。
    /// JSONEncoder でエスケープし、ローカライズ済み文字列に引用符等が含まれても
    /// JS オブジェクトリテラルを壊さないようにする。
    public static func findStringsScript(bundle: Bundle = .main) -> String {
        let strings: [String: String] = [
            "placeholder": String(localized: "viewer.find.placeholder", bundle: bundle),
            "previous": String(localized: "viewer.find.previous", bundle: bundle),
            "next": String(localized: "viewer.find.next", bundle: bundle),
            "matchCase": String(localized: "viewer.find.matchCase", bundle: bundle),
            "matchWholeWord": String(localized: "viewer.find.matchWholeWord", bundle: bundle),
            "useRegularExpression": String(localized: "viewer.find.useRegularExpression", bundle: bundle),
            "close": String(localized: "viewer.find.close", bundle: bundle),
        ]
        guard let jsonData = try? JSONEncoder().encode(strings),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return "window._mmdFindStrings = {};"
        }
        return "window._mmdFindStrings = \(jsonString);"
    }
}
