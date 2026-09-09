import PDFKit

/// 回転の**補間を残さない**ための、レイヤーアニメーションの剥がし役。
///
/// PDF の面そのものの責務ではなく CoreAnimation の回避策なので、
/// `ZoomingPDFView` から独立させてある(TASK-604.5)。面の stored property は読まず、
/// 剥がす起点となるビューだけを引数で受ける。
enum PDFRotationAnimationStripper {
    /// 回した結果の矩形を最初のフレームから見せる。
    ///
    /// PDFKit は回転後の再レイアウトで、ページのレイヤーへ position / bounds の
    /// `CAAnimation` を明示的に積む。モデル値(`layer.bounds`)は同期に確定するが
    /// `presentation()` だけが約 250ms かけて追いつくため、ページの矩形が
    /// 書き変わっていく過程が見える(実測 / 1 ページ 612x792 の PDF を 90 度:
    /// +14.0ms 612x792 → +87.5ms 703x701 → +237.5ms 791x613 / TASK-576)。
    /// Preview.app は同じ操作が一瞬で終わる。
    ///
    /// 抑止できるのは**剥がすことだけ**で、積ませない手は無い。
    /// `CATransaction.setDisableActions(true)` も `setAnimationDuration(0)` も
    /// 効かない(どちらも暗黙アニメーションへの手当てで、明示的に `add` された
    /// ものは止まらない)。同じ `PDFDocument` を入れ直してレイヤーごと作り直す形も
    /// 試したが、PDFKit はレイヤーを使い回すので補間はそのまま出た(実測 / TASK-576)。
    ///
    /// **`CATransaction.flush()` に依存している。** ここまで来た時点ではまだ
    /// アニメーションは積まれておらず(実測: 回した直後の走査で 0 件)、PDFKit は
    /// CoreAnimation のコミットに合わせて積む。`flush()` でそのコミットを同期に
    /// 走らせて初めて剥がす対象が現れる(実測: 10 件)。
    ///
    /// これは PDFKit が「いつ積むか」への依存であって、そこが変われば
    /// **剥がす対象が 0 件になり、補間がまた見えるようになる**。落ちはせず、
    /// 見た目だけが起票時の状態へ戻る。`PDFSurfaceRotationTests` の
    /// `rotationLeavesNoLayerAnimations` がその状態で落ちる。
    ///
    /// 剥がす範囲を `documentView` 配下のレイヤー木全体にしてあるのは、
    /// PDFKit の内部レイヤー構成(クラス名・階層の深さ)を判定に持ち込まないため。
    /// この面のこの瞬間に走っていてよいレイヤーアニメーションは他に無い
    /// (キーボードスクロールの `NSAnimationContext` は `clipView` の側で、
    /// `documentView` の外)。
    static func strip(under documentView: NSView?) {
        CATransaction.flush()
        var stack = [documentView?.layer].compactMap(\.self)
        while let layer = stack.popLast() {
            layer.removeAllAnimations()
            stack += layer.sublayers ?? []
        }
    }
}
