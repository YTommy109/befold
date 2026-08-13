import AppKit

/// ビューアウィンドウの「器」——`NSWindow` そのものの生成・外観・タイトル追従・
/// 初期フレームの決定を受け持つ。
///
/// `ViewerWindowController` から切り出しているのは行数の都合ではなく、
/// **ここが文書の状態も他の窓の存在も知らない**ためである。入力はファイル URL・
/// フレーム記述子・「その位置が埋まっているか」の述語だけで、`ViewerStore`・表示モード・
/// 永続化ストア・`NSApp.windows` のいずれにも触れない。
///
/// 逆に、ここへ置かないものは次のとおり。
/// - フレームを**いつ**保存するか(`NSWindowDelegate` の契機)は文書の状態の話なのでコントローラ側
/// - 「他のビューア窓と重なっているか」の判定はコントローラ側(述語として受け取る)
@MainActor
enum ViewerWindowChrome {
    /// 保存済みフレームが無いときに使う既定サイズ。
    static let defaultContentSize = NSSize(width: 1100, height: 850)

    /// ビューアウィンドウを 1 枚作る。
    ///
    /// ウィンドウの実サイズは `contentViewController` の設定後に確定させるため、
    /// ここでの `contentRect` はプレースホルダ。
    static func makeWindow(fileURL: URL) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 400, height: 300)
        // コンテンツの地の色はウィンドウ背景が唯一の定義(ViewerTheme.canvas)。
        // WebView は透過(drawsBackground=false)のためこの色が透けて見える
        window.backgroundColor = ViewerTheme.canvas
        // 標準タイトルバーは背景色の上にマテリアルを重ねるため、背景色を
        // 揃えてもわずかに明るく描かれる。透過させて背景色を直接見せ、
        // 区切り線も消してコンテンツと完全に地続きにする
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.tabbingIdentifier = "ViewerWindow"
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        // 生成時点では一覧がまだ届いておらず、出すのは開こうとしている文書。
        applyURL(fileURL, presenting: .undetermined, to: window)
        return window
    }

    /// ウィンドウのタイトルと `representedURL` を、**いま提示しているもの**に合わせて更新する。
    ///
    /// 生成時・リネーム・ファイル切替・提示対象の変化が共有する表示更新で、
    /// **タイトルの導出はここ 1 箇所だけ**。フォルダー一覧を出している間は文書ではなく
    /// そのフォルダーを指す(TASK-469)。文書側だけを見ていた頃は、サイドバーで
    /// フォルダーを選んで一覧を出してもタイトルとプロキシアイコンが直前のファイルの
    /// ままだった。
    ///
    /// `previewTarget` を **既定値の無い引数で受ける**のは、呼び出し側に「いま何を
    /// 提示しているか」を必ず書かせるため。既定値を持たせると、渡し忘れが
    /// コンパイルエラーにならないまま文書名へ戻る経路ができる。
    ///
    /// 現在 URL 自体は `ViewerStore` が保持するため、ここでは複製・代入せず
    /// ウィンドウの見た目だけを追従させる。`representedURL` はタイトルバーの
    /// プロキシアイコン(cmd+クリックのパス表示・タイトルバーからのドラッグ)を有効にする。
    static func applyURL(_ fileURL: URL, presenting previewTarget: PreviewTarget, to window: NSWindow) {
        let target = previewTarget.folderURL ?? fileURL
        window.title = target.lastPathComponent
        window.representedURL = target
    }

    /// 初期フレームを決める。
    ///
    /// `contentViewController` の設定でウィンドウがビューのフィッティングサイズへ
    /// リサイズされるため、呼ぶのはその後にすること。`frameDescriptor` はフレーム座標系で
    /// 保存・復元されるため、タイトルバー高さの混入によるサイズのずれは起きない。
    ///
    /// - Parameter isOccupied: その原点に既に別の窓が居るか。自身の保存値・引き継ぎ値の
    ///   どちらでも、既存ウィンドウと位置が完全に一致すると重なって見分けが付かなくなるため、
    ///   埋まっている間はカスケード量だけずらす。判定に必要な「他のビューア窓」の知識は
    ///   呼び出し側が持つ(この型は `NSApp` を知らない)。
    static func applyInitialFrame(
        _ descriptor: String?, to window: NSWindow, isOccupied: (NSPoint) -> Bool
    ) {
        guard let descriptor else {
            window.setContentSize(defaultContentSize)
            window.center()
            return
        }
        window.setFrame(from: descriptor)
        offsetFrameToAvoidOverlap(window, isOccupied: isOccupied)
    }

    /// 位置が埋まっている間だけ、標準のカスケード量ずらす。
    /// `cascadeTopLeft(from:)` は移動先を戻り値で返すため、戻り値を自分に適用する。
    /// ずらした先がまた別ウィンドウと一致することがあるので、空くまで繰り返す。
    static func offsetFrameToAvoidOverlap(_ window: NSWindow, isOccupied: (NSPoint) -> Bool) {
        var attempts = 0
        while isOccupied(window.frame.origin), attempts < 20 {
            let shifted = window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
            window.setFrameTopLeftPoint(shifted)
            attempts += 1
        }
    }
}
