import PDFKit

/// SwiftUI 内部で生成される `PDFView` を AppKit 側(メニューアクション)へ公開するプロキシ。
///
/// `WebViewProxy` と同じ役割で、面ごとに 1 つ持つ。窓が面そのものを stored property で
/// 抱えない(`DocumentSurfaces` が束ねる)ための橋渡しであり、参照は weak にする
/// (View 階層が所有者で、こちらは覗くだけ)。
@MainActor
final class PDFViewProxy {
    /// **型は `ZoomingPDFView` に絞る。** 倍率を覚えるのは面（`zoom`）なので、
    /// 素の `PDFView` を受けられる形にすると `as?` が外れたときに
    /// 「倍率が保存されない」形で無音に壊れる(TASK-567 のレビュー指摘)。
    weak var pdfView: ZoomingPDFView?

    init() {}
}
