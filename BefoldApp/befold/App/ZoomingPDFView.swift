import PDFKit

/// PDF の面。**この面への書き込みはすべてここを通る**(TASK-574.1)。
///
/// 面の中で完結する倍率操作(ピンチ・Ctrl+ホイール)を受け、文書の差し替え手順を
/// `present(document:rotation:zoom:scrollFraction:)` として同期 1 本で持つ。
/// 換算(いまの倍率・フィット倍率・表示位置)は `PDFSurfaceLayout` が持ち、
/// こちらはそれを読んで面へ書くだけ。書き込み口が 1 つであることが、
/// 倍率が別経路から上書きされる形(TASK-572)を型で防ぐ。
///
/// スクロールそのものは `PDFView` に任せる。かつてはホイールをページ送りへ
/// 振り替えていたが(`PagingPDFView` / TASK-564.2)、連続スクロールへ改めた時点で
/// 不要になった(TASK-567)。
final class ZoomingPDFView: PDFView {
    /// ピンチ・Ctrl+ホイールで倍率が変わったことを窓へ伝える。メニュー経由の
    /// ⌘+ / ⌘- / ⌘0 は `DocumentCommandController` が返り値で伝えるので、ここは
    /// **面の中で完結する操作だけ**の通知口(TASK-564.4)。
    var onZoomChanged: ((Double) -> Void)?
    /// この面がいま見せている倍率(1.0 = ページ全体が収まる)。**面が覚える**ことで、
    /// リサイズや回転をまたいでも意味が保たれる。書き込みは `apply(zoom:)` を通す。
    var zoom: Double = ZoomStore.defaultZoom
    /// 倍率の上下限。`ZoomStore` と同じ値を使い、面ごとに範囲が違う状態を作らない。
    private let minZoom = ZoomStore.minZoom
    private let maxZoom = ZoomStore.maxZoom
    /// 認識器の累積値から増分を出す帳簿。
    private var magnificationTracker = MagnificationTracker()

    // MARK: - 生成

    /// **設定と配線は init で済ませる。** `layout()` のフラグで一度きりの配線を
    /// する形にしていたが(かつての `hasFinishedOneTimeSetup`)、その形だと
    /// 「まだ設定されていない面」が存在できてしまい、呼び忘れが無音で壊れる。
    /// init へ畳めば未設定の面はそもそも作れない(TASK-574.1)。
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpSurface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; this view is created in code only")
    }

    /// 面の基本設定と一度きりの配線。**全ページを縦に連ねて描く**(`.singlePageContinuous`)。
    ///
    /// 当初は `.singlePage` にして、ホイールをページ送りへ振り替えていた
    /// (TASK-564.2)。「2 ページの端が同時に見える位置で止まらない」ことを
    /// 構造で守れるのが理由だったが、その代償としてスクロールでページが瞬時に
    /// 切り替わり、滑らかに読めなかった。**体感を優先してこの不変条件を捨てる**
    /// (TASK-567)。止め方の仕掛け(スナップ・遷移アニメーション)は足さない。
    /// 不変条件を守るために機構を増やすのは単純化の逆方向であるため。
    private func setUpSurface() {
        displayMode = .singlePageContinuous
        displayDirection = .vertical
        // **`autoScales` は使わない。** 連続スクロールでの `PDFView` の自動追従は
        // 幅基準で、ページの下端が画面外に出る(実測: 面 400x500 / Letter で
        // ページ高 517.65pt)。`scaleFactorForSizeToFit` を上書きしても
        // 自動追従はそちらを読まない(実測: 回転後に幅基準へ戻る)。
        // 倍率はこちらで持ち、リサイズ追従は `layout()` が行う。
        autoScales = false
        // ページの影を描かない。**連続スクロールでは影の描画が支配的なコスト**で、
        // 全ページ分の影がぼかしとして毎フレーム乗る。実測(231 ページ / 800x900 の面で
        // 1 フレーム描くまで): 影あり 36.5ms、影なし 4.3ms(8 倍)。`.singlePage` の
        // 頃は 1 ページ分だけだったので目立たなかったが、連続にすると表示が遅く感じる
        // (TASK-567 のユーザー報告)。ページの区切りは余白と地の色で足りる。
        pageShadowsEnabled = false
        installMagnificationRecognizer()
        observeDocumentChanges()
    }

    // MARK: - 文書の差し替え

    /// 文書を差し替え、記憶していた見え方(回転・倍率・位置)まで入れる。
    /// **順序を持つのはこの 1 本だけで、すべて同期に終わる**(TASK-574.1)。
    ///
    /// 各段の理由:
    /// - **回転は倍率より先**。縦横比が変わるとフィット倍率も変わるため。
    /// - **倍率は最初の 1 フレームより前に確定させる**。レイアウト任せにすると、
    ///   切り替え直後の 1 フレームがフィット前の倍率で描かれ、その後に縮む過程が
    ///   見える(サイドバーで .md → .pdf と送ったときの「レンダリングの経過が見える」/
    ///   TASK-567 のユーザー報告)。
    /// - **位置は面が組み上がってから**。`layoutSubtreeIfNeeded()` で組み上げてから
    ///   入れる。かつては「まだ入らない」ことを `pendingRestoreFraction` という
    ///   保留状態で表し、後のレイアウトで消化していたが、その保留がいつ消化されるかが
    ///   別の順序問題を生んでいた(TASK-573)。ここで組み上げてしまえば保留は要らない
    ///   (実測: この順序で復元した位置は 0.5 ちょうどに入り、メインキュー 1 周後も
    ///   変わらない / TASK-574.1)。
    func present(document: PDFDocument?, rotation: Int, zoom: Double, scrollFraction: Double) {
        // data が nil の間(PDF 以外を表示中)は文書を外す。残すと、別種別を見ている
        // 最中に PDF 面が古い文書を抱え続け、印刷が前のファイルを刷る。
        guard let document else {
            self.document = nil
            return
        }
        self.document = document
        apply(rotation: rotation)
        apply(zoom: zoom)
        layoutSubtreeIfNeeded()
        restore(fraction: scrollFraction)
    }

    // MARK: - 面への書き込み

    /// 倍率を適用する。**倍率は面が覚える**ので、以後のリサイズでも同じ倍率
    /// (1.0 ならフィット)が保たれる。`layout()` がそれを行う。
    func apply(zoom: Double) {
        self.zoom = zoom
        scaleFactor = PDFSurfaceLayout.expectedScaleFactor(of: self, zoom: zoom)
    }

    /// 記憶していた回転角へ合わせる(差分だけ回す)。
    func apply(rotation: Int) {
        let delta = PDFSurfaceLayout.normalized(rotation) - PDFSurfaceLayout.rotation(of: self)
        guard delta != 0 else { return }
        rotate(byDegrees: delta)
    }

    /// 表示を 90 度単位で回す。**文書全体を回す**(現在ページだけではない)。
    ///
    /// 横向きにスキャンされた PDF は文書ごと横倒しになっているのが普通で、
    /// ページ単位だとページを送るたびに回し直すことになる。ページごとに向きが
    /// 混在する PDF では一部が正しくならないが、そちらは例外的な形なので、
    /// 「1 回の操作で読める状態になる」ほうを採る(TASK-564.5)。
    ///
    /// 回転前の倍率(1.0 = フィット)を保つ。縦横比が変わるとフィットの絶対倍率も
    /// 変わるので、回した直後に**同期で**入れ直す。倍率は面が覚えている `zoom` を使う
    /// (`scaleFactor` から逆算すると、文書の差し替え途中では前の文書の値を拾う)。
    ///
    /// **メインキューへ後回しにしてはならない。** かつては回転前の倍率を捕捉して
    /// `DispatchQueue.main.async` で入れ直しており、差し替えが続けて同期で入れた
    /// `initialZoom` を**前のファイルの倍率**で上書きしていた(TASK-572)。後回しに
    /// する理由だった「同期だとまだ古い `scaleFactorForSizeToFit` を読む」は、
    /// `fitScale` を `largestPageSize`(`page.rotation` を織り込む)から同期に計算する
    /// ようになった時点(TASK-567)で消えている。PDFKit 自身の再レイアウトはメイン
    /// キューへ積まれるが、`autoScales` が切れているので倍率には触らない
    /// (実測: 同期で入れた倍率は 200ms 後も同じ値 / TASK-572)。
    func rotate(byDegrees degrees: Int) {
        guard let document else { return }
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            page.rotation = PDFSurfaceLayout.normalized(page.rotation + degrees)
        }
        // フィットで見ていたなら回転後もフィット、拡大していたなら同じ拡大率のまま。
        apply(zoom: zoom)
        settleRotation()
    }

    /// 回転の**補間を残さない**。回した結果の矩形を最初のフレームから見せる。
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
    private func settleRotation() {
        CATransaction.flush()
        var stack = [documentView?.layer].compactMap(\.self)
        while let layer = stack.popLast() {
            layer.removeAllAnimations()
            stack += layer.sublayers ?? []
        }
    }

    /// 文書全体に対する表示位置(0…1)を復元する。
    ///
    /// ページ数が減って記憶した位置が範囲外になっても、**余地の割合で復元する**ので
    /// 行き先は必ず文書の中に収まる(TASK-564.3 の AC #4)。ページ番号で丸めていた
    /// 頃の分岐は要らない。余地が無ければ動かせないので何もしない。
    func restore(fraction: Double) {
        guard let scrollView = documentView?.enclosingScrollView else { return }
        let room = PDFSurfaceLayout.verticalScrollRoom(of: self)
        guard room > 0 else { return }
        var origin = scrollView.contentView.bounds.origin
        origin.y = PDFSurfaceLayout.scrollOffset(forFraction: fraction, room: room)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// 指定量だけアニメーションでスクロールする。**向きの規則は
    /// `PDFSurfaceLayout.scrollOffset(forFraction:room:)` の doc が持つ**(下へ送るほど
    /// y は減る)。キーボード操作の入口(`keyDown`)は方向を決めて委譲するだけにする。
    func scrollSmoothly(by amount: Double) {
        guard let scrollView = PDFSurfaceLayout.scrollView(in: self) else { return }
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        let maxY = max(PDFSurfaceLayout.verticalScrollRoom(of: self), 0)
        origin.y = min(max(origin.y + amount, 0), maxY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.scrollAnimationDuration
            context.allowsImplicitAnimation = true
            clipView.animator().setBoundsOrigin(origin)
        } completionHandler: {
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    /// キーボードスクロールのアニメーション時間。
    private static let scrollAnimationDuration: Double = 0.25

    // MARK: - 検索の表示

    /// 検索の一致を面へ映す（TASK-570）。
    ///
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
    func showFindMatches(_ selections: [PDFSelection], current: PDFSelection?, scroll: Bool = true) {
        for selection in selections {
            selection.color = Self.findMatchColor
        }
        current?.color = Self.currentFindMatchColor
        // **入れ直す前に一度外す。** 同じ配列を入れ直しても PDFKit は再描画せず、
        // `PDFSelection.color` の変更だけでは現在の一致の色が更新されない
        // （実機で確認: 次へ送っても橙のままの位置が動かない / TASK-570）。
        highlightedSelections = nil
        highlightedSelections = selections.isEmpty ? nil : selections
        guard scroll, let current else { return }
        go(to: current)
    }

    /// 検索の表示を消す。バーを閉じたときと、文書を差し替えたときに呼ぶ。
    func clearFindMatches() {
        highlightedSelections = nil
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

    // MARK: - レイアウト

    /// **内側のスクロールビューの拡大縮小をここで切る。** 切らないと
    /// `PDFScrollView` がピンチを消費し、下の `magnify` へ届かない(TASK-568)。
    ///
    /// 設定の入れ場所を `setUpSurface` にはしない。あちらは文書を入れる前に走り、
    /// そのときスクロールビューはまだ無い。文書の差し替えで作り直されることもある。
    /// **レイアウトのたびに入れ直す**のが、呼ぶ順番に依存しない唯一の形
    /// (実測: 生成時だけだと true のまま残る)。
    ///
    /// **この 2 つ以外の仕事をここへ足さない。** かつては一度きりの配線と復元待ちの
    /// 消化も抱えており、いつ走るか分からないレイアウトの中で順序が決まっていた
    /// (TASK-573 / TASK-574.1)。順序を持つのは `present(...)` だけにする。
    override func layout() {
        super.layout()
        PDFSurfaceLayout.scrollView(in: self)?.allowsMagnification = false
        keepZoomAfterLayout()
    }

    /// リサイズ・回転でページの寸法や面の寸法が変わっても、**倍率の意味**
    /// (1.0 = ページ全体が収まる)を保つ。`autoScales` の代わりで、あちらと違い
    /// 幅基準にならない(`PDFSurfaceLayout.fitScale` が定義を持つ)。
    private func keepZoomAfterLayout() {
        let wanted = PDFSurfaceLayout.expectedScaleFactor(of: self, zoom: zoom)
        // 同じ値を入れ直すと再レイアウトが積まれて往復するので、変化したときだけ。
        // 掛け算そのものは持たない(換算式は `PDFSurfaceLayout` の 1 箇所)。
        guard abs(scaleFactor - wanted) > 0.0001 else { return }
        apply(zoom: zoom)
    }

    /// 文書が差し替わったらフィットを計算し直す。ページの寸法が変われば
    /// 1.0 の意味する絶対倍率も変わるため、入れ替えただけでは追従しない
    /// (実測: 別種別から PDF へ戻したとき、前の文書の倍率のまま描かれた)。
    ///
    /// **`document` プロパティを override してはならない。** PDFKit は
    /// `visiblePagesChanged:` からバックグラウンドキューで `document` を読む。
    /// `@MainActor` 隔離された override を置くと、そこで隔離チェックが
    /// `SIGTRAP` を投げてアプリが落ちる(実測: PDFPageAnalyzerV2 の経路で再現 /
    /// クラッシュレポート befold-2026-08-30-060318)。PDFKit が主スレッドで出す
    /// この通知なら安全に受けられる。
    private func observeDocumentChanges() {
        NotificationCenter.default.addObserver(
            forName: .PDFViewDocumentChanged, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsLayout = true }
        }
    }

    // MARK: - 入力

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
    /// (実測できない入口は静かに壊れる。実際、ログを外す作業で `applyZoom` の
    /// 呼び出しごと消えてもテストは全件通った / TASK-568)。
    @objc func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
        let increment = magnificationTracker.increment(for: recognizer)
        guard increment != 0 else { return }
        applyZoom(scaledBy: 1 + increment)
    }

    /// 認識器が返す `magnification` は**ジェスチャ開始からの累積値**なので、
    /// 前回からの増分へ直してから倍率へ掛ける。ジェスチャが終わったら 0 へ戻す。
    /// `NSGestureRecognizer` を作らずに単体で確かめられるよう独立させてある。
    private struct MagnificationTracker {
        private var last: Double = 0

        mutating func increment(for recognizer: NSMagnificationGestureRecognizer) -> Double {
            let increment = recognizer.magnification - last
            last = recognizer.magnification
            if recognizer.state == .ended || recognizer.state == .cancelled { last = 0 }
            return increment
        }
    }

    /// トラックパッドのピンチ。
    ///
    /// **こちらは補助の経路。** 主経路は上の認識器で、`magnify` が呼ばれるには
    /// 内側のスクロールビューの `allowsMagnification` が切れている必要がある
    /// (切るのは `layout`)。既定のままだと `PDFScrollView` がジェスチャを
    /// 消費してここへ届かない(TASK-568 の実測)。
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
        // 送る量の規則は `PDFSurfaceLayout` が持つ。ここは向きを決めるだけ。
        let backwards = event.modifierFlags.contains(.shift)
        let amount = PDFSurfaceLayout.visibleHeight(of: self)
            * PDFSurfaceLayout.keyboardScrollOverlap
        scrollSmoothly(by: backwards ? amount : -amount)
    }

    /// いまの倍率へ係数を掛けて適用し、窓へ伝える。上下限は `ZoomStore` と共有する。
    /// ピンチと Ctrl+ホイールの入口が両方ここへ収斂する(倍率の意味と上下限を
    /// 入口ごとに書かないため)。`NSEvent` を作らずに検証できるよう internal。
    func applyZoom(scaledBy factor: Double) {
        let scaled = min(max(PDFSurfaceLayout.currentZoom(of: self) * factor, minZoom), maxZoom)
        apply(zoom: scaled)
        onZoomChanged?(scaled)
    }
}
