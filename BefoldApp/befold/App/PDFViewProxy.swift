import PDFKit

/// SwiftUI 内部で生成される `PDFView` を AppKit 側(メニューアクション)へ公開するプロキシ。
///
/// `WebViewProxy` と同じ役割で、面ごとに 1 つ持つ。窓が面そのものを stored property で
/// 抱えない(`DocumentSurfaces` が束ねる)ための橋渡しであり、参照は weak にする
/// (View 階層が所有者で、こちらは覗くだけ)。
@MainActor
final class PDFViewProxy {
    weak var pdfView: PDFView?

    init() {}
}
