import PDFKit

/// 面の中で完結する倍率操作(ピンチ・Ctrl+ホイール)を受け取る `PDFView`。
///
/// スクロールそのものは `PDFView` に任せる。かつてはホイールをページ送りへ
/// 振り替えていたが(`PagingPDFView` / TASK-564.2)、連続スクロールへ改めた時点で
/// 不要になった(TASK-567)。
final class ZoomingPDFView: PDFView {
    /// ピンチ・Ctrl+ホイールで倍率が変わったことを窓へ伝える。メニュー経由の
    /// ⌘+ / ⌘- / ⌘0 は `WebViewCommandController` が返り値で伝えるので、ここは
    /// **面の中で完結する操作だけ**の通知口(TASK-564.4)。
    var onZoomChanged: ((Double) -> Void)?
    /// この面がいま見せている倍率(1.0 = ページ全体が収まる)。**面が覚える**ことで、
    /// リサイズや回転をまたいでも意味が保たれる。書き込みは
    /// `PDFSurfaceLayout.apply(zoom:to:)` を通す。
    var zoom: Double = ZoomStore.defaultZoom
    /// 文書を差し替えた直後に復元したい表示位置(0…1)。**すぐには適用しない。**
    /// 倍率が決まる前に位置を入れると、レイアウトが落ち着く過程で
    /// 位置と倍率が数回ずつ動き、開いた瞬間のちらつきになる(TASK-567)。
    /// `layout` が倍率を入れた直後に 1 回だけ使い、使ったら捨てる。
    var pendingRestoreFraction: Double?

    /// 倍率の上下限。`ZoomStore` と同じ値を使い、面ごとに範囲が違う状態を作らない。
    private let minZoom = ZoomStore.minZoom
    private let maxZoom = ZoomStore.maxZoom

    /// **内側のスクロールビューの拡大縮小をここで切る。** 切らないと
    /// `PDFScrollView` がピンチを消費し、下の `magnify` へ届かない(TASK-568)。
    ///
    /// 設定の入れ場所を `PDFSurfaceLayout.configure` にはしない。`configure` は
    /// 文書を入れる前に呼ばれ、そのときスクロールビューはまだ無い。文書の
    /// 差し替えで作り直されることもある。**レイアウトのたびに入れ直す**のが、
    /// 呼ぶ順番に依存しない唯一の形(実測: configure だけだと true のまま残る)。
    override func layout() {
        super.layout()
        if !hasFinishedOneTimeSetup {
            hasFinishedOneTimeSetup = true
            installMagnificationRecognizer()
            observeDocumentChanges()
        }
        PDFSurfaceLayout.scrollView(in: self)?.allowsMagnification = false
        keepZoomAfterLayout()
        applyPendingRestore()
    }

    /// 倍率が決まった後に、待たせていた表示位置を 1 回だけ入れる。
    private func applyPendingRestore() {
        guard let fraction = pendingRestoreFraction else { return }
        // 余地が出るまでは待つ（レイアウト前は 0 で、入れても無視される）。
        guard PDFSurfaceLayout.verticalScrollRoom(of: self) > 0 else { return }
        pendingRestoreFraction = nil
        PDFSurfaceLayout.restore(fraction: fraction, in: self)
    }

    /// リサイズ・回転でページの寸法や面の寸法が変わっても、**倍率の意味**
    /// (1.0 = ページ全体が収まる)を保つ。`autoScales` の代わりで、あちらと違い
    /// 幅基準にならない(`PDFSurfaceLayout.fitScale` が定義を持つ)。
    private func keepZoomAfterLayout() {
        let wanted = PDFSurfaceLayout.fitScale(of: self) * zoom
        // 同じ値を入れ直すと再レイアウトが積まれて往復するので、変化したときだけ。
        guard abs(scaleFactor - wanted) > 0.0001 else { return }
        scaleFactor = wanted
    }

    /// **ピンチはジェスチャ認識器でも受ける。**
    ///
    /// `magnify(with:)` のオーバーライドだけでは届かないことがある。ピンチの
    /// ヒット先は内側の `PDFPageView` で、`PDFScrollView` が
    /// `NSScrollView.magnifyWithEvent:` を持つため、そこで消費されて上まで来ない
    /// (TASK-568 の実測)。`allowsMagnification` を切る手当てはレイアウトの
    /// タイミングに依存するので、**祖先ビューに付けた認識器**という
    /// レスポンダチェーンに依存しない経路を主にする。
    private func installMagnificationRecognizer() {
        let recognizer = NSMagnificationGestureRecognizer(
            target: self, action: #selector(handleMagnification(_:))
        )
        addGestureRecognizer(recognizer)
    }

    /// 認識器からのピンチ。**`NSEvent` を作らずに検証できるよう internal**
    /// （実測できない入口は静かに壊れる。実際、ログを外す作業で `applyZoom` の
    /// 呼び出しごと消えてもテストは全件通った / TASK-568）。
    @objc func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
        // 認識器の magnification は累積値。前回からの増分だけを倍率へ掛ける。
        let increment = recognizer.magnification - lastRecognizedMagnification
        lastRecognizedMagnification = recognizer.magnification
        if recognizer.state == .ended || recognizer.state == .cancelled {
            lastRecognizedMagnification = 0
        }
        guard increment != 0 else { return }
        applyZoom(scaledBy: 1 + increment)
    }

    /// 直前に認識器から受け取った累積値（増分を出すために覚える）。
    private var lastRecognizedMagnification: Double = 0
    /// 1 回だけ行う配線（認識器・通知の購読）。
    private var hasFinishedOneTimeSetup = false

    /// 文書が差し替わったらフィットを計算し直す。ページの寸法が変われば
    /// 1.0 の意味する絶対倍率も変わるため、入れ替えただけでは追従しない
    /// （実測: 別種別から PDF へ戻したとき、前の文書の倍率のまま描かれた）。
    ///
    /// **`document` プロパティを override してはならない。** PDFKit は
    /// `visiblePagesChanged:` からバックグラウンドキューで `document` を読む。
    /// `@MainActor` 隔離された override を置くと、そこで隔離チェックが
    /// `SIGTRAP` を投げてアプリが落ちる（実測: PDFPageAnalyzerV2 の経路で再現 /
    /// クラッシュレポート befold-2026-08-30-060318）。PDFKit が主スレッドで出す
    /// この通知なら安全に受けられる。
    private func observeDocumentChanges() {
        NotificationCenter.default.addObserver(
            forName: .PDFViewDocumentChanged, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsLayout = true }
        }
    }

    /// トラックパッドのピンチ。
    ///
    /// **これが呼ばれるには、内側のスクロールビューの `allowsMagnification` を
    /// 切っておく必要がある**(`PDFSurfaceLayout.configure`)。既定のままだと
    /// `PDFScrollView` がジェスチャを消費してここへ届かない(TASK-568 の実測)。
    override func magnify(with event: NSEvent) {
        applyZoom(scaledBy: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        // Ctrl+ホイールは拡大縮小(viewer.js の _mmdWheelZoom と同じ約束)。
        guard event.modifierFlags.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }
        applyZoom(scaledBy: 1 + event.scrollingDeltaY / 100)
    }

    /// スペース / Shift+スペースを**滑らかな**スクロールにする。
    ///
    /// `PDFView` の既定はページ単位のジャンプで、連続スクロールにした後も
    /// スペースだけ非連続なまま残る(TASK-567 のユーザー報告)。1 画面ぶんを
    /// アニメーションで送ると、トラックパッドの操作感と揃う。
    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else {
            super.keyDown(with: event)
            return
        }
        let backwards = event.modifierFlags.contains(.shift)
        // 下へ送るほど y は**減る**（`PDFSurfaceLayout.scrollOffset` の実測）。
        scrollSmoothly(by: visibleHeight * (backwards ? 1 : -1) * Self.pageOverlap)
    }

    /// 1 回のスペースで送る割合。少し重ねて送ると読んでいた行が画面に残る。
    private static let pageOverlap: Double = 0.9

    /// いま見えている高さ(文書座標)。
    private var visibleHeight: Double {
        guard let scrollView = PDFSurfaceLayout.scrollView(in: self) else { return bounds.height }
        return scrollView.contentView.bounds.height
    }

    /// 指定量だけアニメーションでスクロールする。
    private func scrollSmoothly(by amount: Double) {
        guard let scrollView = PDFSurfaceLayout.scrollView(in: self) else { return }
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        let maxY = max(PDFSurfaceLayout.verticalScrollRoom(of: self), 0)
        origin.y = min(max(origin.y + amount, 0), maxY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            clipView.animator().setBoundsOrigin(origin)
        } completionHandler: { [weak self] in
            guard let self else { return }
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    /// いまの倍率へ係数を掛けて適用し、窓へ伝える。上下限は `ZoomStore` と共有する。
    /// ピンチと Ctrl+ホイールの入口が両方ここへ収斂する(倍率の意味と上下限を
    /// 入口ごとに書かないため)。`NSEvent` を作らずに検証できるよう internal。
    func applyZoom(scaledBy factor: Double) {
        let scaled = min(max(PDFSurfaceLayout.currentZoom(of: self) * factor, minZoom), maxZoom)
        PDFSurfaceLayout.apply(zoom: scaled, to: self)
        onZoomChanged?(scaled)
    }
}
