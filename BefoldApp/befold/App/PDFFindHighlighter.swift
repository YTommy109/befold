import PDFKit

/// 検索の一致を PDF の面へ映す役(TASK-570)。
///
/// `highlightedSelections` はユーザー選択とも倍率・回転・スクロール位置とも別系統の
/// 表示なので、面が持つ書き込みの不変条件(`ZoomingPDFView` の型 doc)の外に置く
/// (TASK-604.5)。一致まで送るスクロールだけは面の `scroll(toFindMatch:)` を通す。
@MainActor
enum PDFFindHighlighter {
    /// `highlightedSelections` は**ユーザー選択とは別の系統**で、クリックしても消えない
    /// （PDFKit のヘッダが全マッチのハイライト用途として挙げている）。全件をここへ入れ、
    /// 現在の 1 件だけ色を変えて、web 面の `mark.mmd-find-match` / `-current` の
    /// 2 段階に対応させる。
    ///
    /// **`currentSelection` は使わない。** そちらは PDFKit がシステムの選択色で描く
    /// 系統で、`PDFSelection.color` を見ない。実機で入れたところ、指定した色ではなく
    /// 青が出たうえ、一致の位置とずれた範囲（前の行にまたがる矩形）が描かれた。
    /// 選択は「ユーザーが選んだ範囲」を表すものとして空けておく。
    ///
    /// - Parameter scroll: 現在の一致まで送るか。検索の進行中に件数だけが増えていく間は
    ///   false にする。毎回送ると、まだ読んでいる最中に画面が飛び続ける。
    static func show(
        _ selections: [PDFSelection], current: PDFSelection?,
        in view: ZoomingPDFView, scroll: Bool = true
    ) {
        for selection in selections {
            selection.color = findMatchColor
        }
        current?.color = currentFindMatchColor
        // **入れ直す前に一度外す。** 同じ配列を入れ直しても PDFKit は再描画せず、
        // `PDFSelection.color` の変更だけでは現在の一致の色が更新されない
        // （実機で確認: 次へ送っても橙のままの位置が動かない / TASK-570）。
        view.highlightedSelections = nil
        view.highlightedSelections = selections.isEmpty ? nil : selections
        guard scroll, let current else { return }
        view.scroll(toFindMatch: current)
    }

    /// 検索の表示を消す。バーを閉じたときと、文書を差し替えたときに呼ぶ。
    static func clear(in view: ZoomingPDFView) {
        view.highlightedSelections = nil
    }

    /// 一致の色。web 面の `mark.mmd-find-match`（rgba(255, 213, 0, 0.55)）に合わせる。
    private static let findMatchColor = NSColor(
        srgbRed: 1.0, green: 213.0 / 255.0, blue: 0, alpha: 0.55
    )
    /// 現在の一致の色。web 面の `mark.mmd-find-match-current`（--accent）に対応する。
    /// **ユーザー選択と同じ色にしない**（PDFKit のヘッダの推奨。どれが検索結果で
    /// どれが自分で選んだ範囲かが見分けられなくなる）。他の一致（薄い黄）との差が
    /// 一目で分かるよう、彩度の高いオレンジにする。
    private static let currentFindMatchColor = NSColor.systemOrange.withAlphaComponent(0.75)
}
