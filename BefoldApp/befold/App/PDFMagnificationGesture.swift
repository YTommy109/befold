import AppKit

/// ピンチを**倍率の増分**へ直して届ける入力アダプタ（TASK-577）。
///
/// `NSMagnificationGestureRecognizer` の `magnification` は**ジェスチャ開始からの
/// 累積値**なので、そのまま倍率へ掛けると 1 回のピンチで指数的に伸びる。前回からの
/// 増分へ直す帳簿がここの本体で、認識器の所有もまとめて引き受ける。
///
/// **面から分けてあるのは、これが「面であること」と無関係だから。** `ZoomingPDFView` は
/// 倍率の意味と上下限を持ち、こちらは入力の形を直すだけで、PDF も倍率も知らない。
/// （分けた直接のきっかけは型グループの行数超過だが、行数だけが理由なら extension で
/// 足りる。合算で数える `scripts/check-type-group-size.sh` はその逃げ道を塞ぐためにあり、
/// ここは実際に別の関心なので型ごと出している。）
///
/// **ピンチはジェスチャ認識器で受ける。** `magnify(with:)` のオーバーライドだけでは
/// 届かないことがある。ピンチのヒット先は内側の `PDFPageView` で、`PDFScrollView` が
/// `NSScrollView.magnifyWithEvent:` を持つため、そこで消費されて上まで来ない
/// （TASK-568 の実測）。`allowsMagnification` を切る手当てはレイアウトのタイミングに
/// 依存するので、**祖先ビューに付けた認識器**というレスポンダチェーンに依存しない
/// 経路を主にする。
@MainActor
final class PDFMagnificationGesture: NSObject {
    /// 前回までの累積値。ジェスチャが終わったら 0 へ戻す。
    private var last: Double = 0
    /// 増分の届け先。倍率へどう掛けるかは受け手（`ZoomingPDFView.applyZoom(scaledBy:)`）が決める。
    private let onIncrement: (Double) -> Void

    /// 認識器を `view` へ付け、以後の増分を `onIncrement` へ流す。
    /// 認識器はビューが保持するので、こちらは自身を target として渡すだけでよい。
    init(attachedTo view: NSView, onIncrement: @escaping (Double) -> Void) {
        self.onIncrement = onIncrement
        super.init()
        view.addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: self, action: #selector(handle(_:)))
        )
    }

    /// 認識器からのピンチ。**`NSEvent` を作らずに検証できるよう internal**
    /// （実測できない入口は静かに壊れる。実際、ログを外す作業で `applyZoom` の
    /// 呼び出しごと消えてもテストは全件通った / TASK-568）。
    @objc func handle(_ recognizer: NSMagnificationGestureRecognizer) {
        let increment = recognizer.magnification - last
        last = recognizer.magnification
        if recognizer.state == .ended || recognizer.state == .cancelled { last = 0 }
        guard increment != 0 else { return }
        onIncrement(increment)
    }
}
