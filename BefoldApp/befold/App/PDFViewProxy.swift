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

    /// キーボードのフォーカスを**面へ戻す**。
    ///
    /// PDF の上に重なる SwiftUI の入力欄（ページ番号・検索）を閉じたときの戻し先は、
    /// 常に「いま読んでいる面」。出す前の first responder へ返す形にしていたことが
    /// あるが、実測ではそれがサイドバーのファイル一覧で、閉じた直後に ↓ を押すと
    /// 選択が動いて**別のファイルが開いた**（TASK-578.2）。
    ///
    /// **1 周待つ。** 入力欄が消えるより先に移すと、その後の View の片付けで
    /// first responder が外れる（実測 / TASK-578.2）。
    ///
    /// **開いた契機がユーザー操作のときだけ呼ぶこと。** 文書の差し替えなど、
    /// ユーザーが操作していない契機で呼ぶと、サイドバーを矢印で流し読みしている
    /// 最中にフォーカスを奪う（TASK-581 で起きた回帰）。
    func focusSurface() {
        let surface = pdfView
        DispatchQueue.main.async {
            guard let surface, let window = surface.window else { return }
            window.makeFirstResponder(surface)
        }
    }
}
