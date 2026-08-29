import AppKit
import BefoldKit
import PDFKit

/// `DocumentRendering` の PDFKit 実装(ADR 0002 段 4 の 2 枚目の adapter)。
///
/// `PDFView` の倍率計算と印刷という「どう実現するか」をここに閉じる。
/// 呼び出し側(`WebViewCommandController`)は WKWebView 版との違いを知らない
/// (宛先を決めるのは `DocumentSurfaces` だけ / ADR 0009)。
@MainActor
final class PDFDocumentRenderer: DocumentRendering {
    private let pdfViewProxy: PDFViewProxy
    /// 倍率の刻みと上下限。PDF には viewer.js が居ないため、直接 HTML モードと同じく
    /// 自前で計算して呼び出し側へ返す(保存はあちらの責務)。
    private let zoomStep: Double
    private let minZoom: Double
    private let maxZoom: Double
    private let defaultZoom: Double

    init(
        pdfViewProxy: PDFViewProxy,
        zoomStep: Double = ZoomStore.zoomStep,
        minZoom: Double = ZoomStore.minZoom,
        maxZoom: Double = ZoomStore.maxZoom,
        defaultZoom: Double = ZoomStore.defaultZoom
    ) {
        self.pdfViewProxy = pdfViewProxy
        self.zoomStep = zoomStep
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.defaultZoom = defaultZoom
    }

    /// PDF は viewer.html を使わないが、直接 HTML モード(HTML ファイルを WebKit へ
    /// 丸ごと渡している状態)ではない。この値は「viewer.js の検索が使えるか」を
    /// 表すもので、PDF で検索できないことは能力側(`canFind` の `!isBinaryContent`)が表す。
    var isDirectHTMLMode: Bool {
        false
    }

    // MARK: - Zoom

    /// 倍率 1.0 = ページ全体がビューに収まる状態。`PDFView` の `scaleFactor` は
    /// 絶対倍率なので、収まる倍率を基準に掛け直す。こうしないと、同じ 1.0 が
    /// WebView 側では等倍・PDF 側ではページの一部という別の意味になる。
    /// 換算そのものは `PDFSurfaceLayout` が持つ(面の生成側と同じ規則を通す)。
    func applyZoom(_ zoom: Double) {
        guard let pdfView = pdfViewProxy.pdfView else { return }
        PDFSurfaceLayout.apply(zoom: zoom, to: pdfView)
    }

    func changeZoom(_ change: ZoomChange) -> Double? {
        guard let pdfView = pdfViewProxy.pdfView else { return nil }
        let newZoom = stepped(change, current: PDFSurfaceLayout.currentZoom(of: pdfView))
        applyZoom(newZoom)
        return newZoom
    }

    // MARK: - Find / Jump

    /// PDF 内検索とジャンプは持たない。**能力側で塞いであるのでここへは来ない**
    /// (`canFind` / `canJump` が `!isBinaryContent`)。押せるのに何も起きない形を
    /// 作らないための約束であり、no-op で握り潰すためのものではない。
    /// PDF 内検索を実装するときは、能力の条件と一緒に開けること。
    func openFind() {}
    func findNext() {}
    func findPrevious() {}
    func openJump(kind: DocumentJumpKind) {}

    // MARK: - Print

    /// `capabilities.canPrint` は PDF でも true なので、実体を持たせる
    /// (能力が true なのに何も起きない形は ADR 0002 が排した)。
    func printDocument(over window: NSWindow?) {
        guard let window, let document = pdfViewProxy.pdfView?.document else { return }
        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        guard let operation = document.printOperation(
            for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true
        ) else { return }
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - Scroll position

    /// 表示位置を 0…1 の割合で返す(JS 側の `currentScrollPosition` と同じ意味)。
    /// PDF ではページ番号とページ内の位置を同じ 0…1 へ畳む(`PDFSurfaceLayout`)。
    /// 面がまだ無いときは完了を呼ばない(`DocumentSurfaceOperating` の契約)。
    func currentScrollPosition(_ completion: @escaping (Double) -> Void) {
        guard let pdfView = pdfViewProxy.pdfView else { return }
        completion(PDFSurfaceLayout.documentFraction(of: pdfView))
    }

    // MARK: - Rotation

    /// 文書全体を 90 度単位で回す(範囲の判断は `PDFSurfaceLayout` の doc)。
    func rotate(byDegrees degrees: Int) {
        guard let pdfView = pdfViewProxy.pdfView else { return }
        PDFSurfaceLayout.rotate(byDegrees: degrees, in: pdfView)
    }

    var currentRotation: Int {
        pdfViewProxy.pdfView.map { PDFSurfaceLayout.rotation(of: $0) } ?? 0
    }

    // MARK: - 追随(全面へ配られる)

    /// ソース表示のフォントも CSV の数値表示も PDF には無い。**配られること自体は正しい**
    /// (宛先を種別で振り分けると、PDF を見ている間の設定変更が WebView 側へ入らない)。
    /// 受け取って何もしないのがこの面の正しい追随。
    func applyCodeFont(family: String?, points: Double?) {}
    func applyCsvNumberFormat(grouping: Bool, negativeStyle: CsvNegativeStyle) {}
    func applyJumpAvailability(_ kinds: Set<DocumentJumpKind>) {}

    /// PDF 面は描画済みミラーも JS 側の文書パスも持たない(描くのは `Data` だけで、
    /// パスに依存する状態が無い)。リネームで追随すべきものがそもそも無い。
    func noteRename(from oldURL: URL, to newURL: URL) {}

    // MARK: - Private

    private func stepped(_ change: ZoomChange, current: Double) -> Double {
        switch change {
        case .zoomIn: min(maxZoom, current + zoomStep)
        case .zoomOut: max(minZoom, current - zoomStep)
        case .reset: defaultZoom
        }
    }
}
