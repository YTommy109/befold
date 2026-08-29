/// PDF の面と窓のあいだの受け渡し。
///
/// 面の中で完結する倍率操作（ピンチ・Ctrl+ホイール）の通知と、重ねたコントロールから
/// の回転の要求をまとめる。クロージャを 1 つずつ View の引数へ足すと注入が 3 つを
/// 超えるため、PDF 面まわりの受け渡しはこの 1 つの値に閉じる
/// （`docs/dev/rules/product-code.md` の責務分離節）。
struct PDFSurfaceActions {
    /// 面の中で倍率が変わったことを窓へ伝える。メニュー経由の倍率変更はここを通らない
    /// （コマンド側が返り値で伝える）。
    let onZoomChanged: (Double) -> Void
    /// 90 度単位の回転を要求する。時計回りが正。可否の判断は窓側（`canRotate`）。
    let onRotate: (Int) -> Void
}
