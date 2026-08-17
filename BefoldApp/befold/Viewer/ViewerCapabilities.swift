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
    /// 文書内ジャンプ(目印の前後移動)。検索と同じく viewer.html の JS を要するため
    /// HTML 直接ロード中は不可。開発中機能なので、ゲートが閉じている間も不可
    /// (`FeatureGate.isDocumentJumpEnabled` を `ViewerCapabilitiesFactory` が渡す)。
    let canJump: Bool
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
    /// モード切替のうち「差分表示」を選べるか。行番号と同じく
    /// 「いまソース相当の内容を出している」ときだけ意味を持つ。
    let canSelectDiffMode: Bool
    /// 差分レイアウト(上下/左右)の切替。差分表示を選んでいる間だけ意味を持つ。
    let canToggleDiffLayout: Bool

    /// - Parameters:
    ///   - isPresentingDocument: 文書を提示しているか。フォルダー一覧を出している間は false。
    ///     一覧が届く前(未確定)は、開こうとしている文書を提示しているものとして扱う。
    ///   - isRejected: 表示できないファイルとして拒否されているか。
    ///   - isRenderable: プレビュー表示できる種別か。
    ///   - isBinaryContent: テキストソースを持たない種別(画像・PDF)か。
    ///   - showsCodeContent: いまソース相当の内容を表示しているか。
    ///   - showsDiff: いま差分表示モードを選んでいるか。
    ///   - supportsSourceMode: ソース表示への切替を持つ種別か。
    ///   - supportsDiffDisplay: ソース表示へ差分を重ねられる種別か(CSV/TSV は不可)。
    ///   - gitDiffAvailability: 差分を出せる git の事実(可用性・変更の有無)。
    ///     ADR(libgit2 移行)の Fallback にある「git が使えないとき差分表示モードを
    ///     選択不可にする」はここから来る。
    ///   - isDirectHTMLMode: HTML を直接ロードして表示しているか。
    ///   - isDocumentJumpEnabled: 文書内ジャンプを露出してよいか(開発中機能のゲート)。
    ///     既定値は持たせない。渡し忘れが静かに「常に有効」へ倒れると、stable へ
    ///     開発中の機能が載る形になるため。
    init(
        isPresentingDocument: Bool,
        isRejected: Bool,
        isRenderable: Bool,
        isBinaryContent: Bool,
        showsCodeContent: Bool,
        showsDiff: Bool = false,
        supportsSourceMode: Bool,
        supportsDiffDisplay: Bool,
        gitDiffAvailability: GitDiffAvailability,
        isDirectHTMLMode: Bool,
        isDocumentJumpEnabled: Bool
    ) {
        let onDocument = isPresentingDocument && !isRejected
        canPrint = onDocument
        canFind = onDocument && !isDirectHTMLMode
        // 目印が 0 個かどうかでは判定しない。段階読み込み中・描画前・取得失敗の
        // いずれでも同じ 0 個になり、事実ではなくデータの空きで縮退することになる。
        // 目印が無いことは viewer 側の 0/0 表示が伝える。
        canJump = onDocument && !isDirectHTMLMode && isDocumentJumpEnabled
        canZoom = onDocument
        canToggleSourceMode = onDocument && supportsSourceMode
        canSelectPreviewMode = onDocument && isRenderable
        canSelectSourceMode = onDocument && !isBinaryContent
        canToggleLineNumbers = isPresentingDocument && showsCodeContent
        canBookmark = isPresentingDocument
        // 差分は「いまソースを出しているか」ではなく「その種別がソースと差分を出せるか」で
        // 決める。差分を選ぶこと自体がソース表示へ移る操作なので、現在の表示内容で判定すると
        // レンダリング表示中は差分セグメント(⌘3)が押せず、一度ソースへ寄ってからでないと
        // 差分へ行けない。判定条件はソース表示の選択可否 + 差分を描ける種別か。
        // 種別だけでなく git 側の事実も見る。ここを見ないと、git を使えないディレクトリや
        // 変更の無いファイルでも差分を選べてしまい、押した結果は
        // `ViewerDiffPresenter.displayableDiff(_:)` が黙って通常のソース表示へ戻す
        // (= 反応が無いように見える / TASK-438.2)。
        canSelectDiffMode = onDocument && !isBinaryContent && supportsDiffDisplay
            && gitDiffAvailability.allowsDiffSelection
        canToggleDiffLayout = canSelectDiffMode && showsDiff
    }

    /// そのモードをいま選べるか。モード別のフラグを引き当てるだけの対応表であり、
    /// 条件そのものは上の init が持つ(ADR 0002 段 2 の「条件は 1 箇所」)。
    /// ツールバーのセグメントとメニューの有効判定が共有する。
    func canSelect(_ mode: ViewerDisplayMode) -> Bool {
        switch mode {
        case .rendered: canSelectPreviewMode
        case .source: canSelectSourceMode
        case .diff: canSelectDiffMode
        }
    }

    /// 何もできない状態(文書を提示していない)。テストとフォールバックの既定値。
    static let none = ViewerCapabilities(
        isPresentingDocument: false,
        isRejected: false,
        isRenderable: false,
        isBinaryContent: false,
        showsCodeContent: false,
        supportsSourceMode: false,
        supportsDiffDisplay: false,
        gitDiffAvailability: .undetermined,
        isDirectHTMLMode: false,
        isDocumentJumpEnabled: false
    )
}
