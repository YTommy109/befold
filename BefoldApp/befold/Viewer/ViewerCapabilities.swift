import Foundation

/// 「いまこの操作が可能か」を提示状態から導出した値(ADR 0002 段 2)。
///
/// メニューの有効判定・ツールバーの有効判定・コマンドの実行ガードは、すべてここだけを見る。
/// 以前は判断が 3 箇所に分かれ、さらに「WKWebView が破棄されて weak 参照が nil になる」
/// という**ビューの生存期間**が実質的な無効化を担っていた。ビューを常駐させた途端に
/// その暗黙の無効化が消え、見えていない文書へ操作が届くようになった(TASK-266 → 271)。
///
/// Cocoa では validate を実装しなければメニュー項目は有効になる。無効化は明示的に
/// 書くものであり、参照が nil であることに任せてはならない。
struct ViewerCapabilities: Equatable {
    /// 印刷。見えている文書に対してのみ許す。
    let canPrint: Bool
    /// 検索(⌘F / ⌘G)。HTML 直接ロード中は viewer.html の JS が無いため不可。
    let canFind: Bool
    /// ズーム(拡大・縮小・等倍)。
    let canZoom: Bool
    /// View メニューのソース表示トグル。種別がソース表示を持つときのみ。
    let canToggleSourceMode: Bool
    /// モード切替のうち「プレビュー表示」を選べるか。
    let canSelectPreviewMode: Bool
    /// モード切替のうち「ソース表示」を選べるか。
    let canSelectSourceMode: Bool
    /// 行番号の表示切替。ソース相当の内容を表示しているときのみ意味を持つ。
    let canToggleLineNumbers: Bool
    /// ブックマークの付け外し。対象は「いま見えている文書」。
    let canBookmark: Bool
    /// git 差分表示の切替。行番号と同じく「いまソース相当の内容を出している」ときだけ意味を持つ。
    let canToggleDiff: Bool

    /// - Parameters:
    ///   - isPresentingDocument: 文書を提示しているか。フォルダー一覧を出している間は false。
    ///     一覧が届く前(未確定)は、開こうとしている文書を提示しているものとして扱う。
    ///   - isRejected: 表示できないファイルとして拒否されているか。
    ///   - isRenderable: プレビュー表示できる種別か。
    ///   - isBinaryContent: テキストソースを持たない種別(画像・PDF)か。
    ///   - showsCodeContent: いまソース相当の内容を表示しているか。
    ///   - supportsSourceMode: ソース表示への切替を持つ種別か。
    ///   - isDirectHTMLMode: HTML を直接ロードして表示しているか。
    init(
        isPresentingDocument: Bool,
        isRejected: Bool,
        isRenderable: Bool,
        isBinaryContent: Bool,
        showsCodeContent: Bool,
        supportsSourceMode: Bool,
        isDirectHTMLMode: Bool
    ) {
        let onDocument = isPresentingDocument && !isRejected
        canPrint = onDocument
        canFind = onDocument && !isDirectHTMLMode
        canZoom = onDocument
        canToggleSourceMode = onDocument && supportsSourceMode
        canSelectPreviewMode = onDocument && isRenderable
        canSelectSourceMode = onDocument && !isBinaryContent
        canToggleLineNumbers = isPresentingDocument && showsCodeContent
        canBookmark = isPresentingDocument
        canToggleDiff = isPresentingDocument && showsCodeContent
    }

    /// 何もできない状態(文書を提示していない)。テストとフォールバックの既定値。
    static let none = ViewerCapabilities(
        isPresentingDocument: false,
        isRejected: false,
        isRenderable: false,
        isBinaryContent: false,
        showsCodeContent: false,
        supportsSourceMode: false,
        isDirectHTMLMode: false
    )
}
