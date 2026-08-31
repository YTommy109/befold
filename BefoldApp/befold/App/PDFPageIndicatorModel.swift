import AppKit
import PDFKit

/// PDF 面の「現在ページ / 総ページ数」（TASK-578.1）。窓ごとに 1 個。
///
/// **面を直接触らない。** 値は `PDFViewProxy` 越しに読むだけで、面へは何も書かない
/// （面への書き込み口を 1 つに保つ約束 / TASK-574.1）。`PDFFindModel` と同じ形。
///
/// **値を溜めない。** 通知を受けたらその場で面から読み直して置き換える。
/// 面と食い違う値を保持しないので、回転・倍率・文書の差し替えのどれで
/// 表示が変わっても、次の通知で必ず実態へ揃う。
@MainActor
@Observable
final class PDFPageIndicatorModel {
    /// いま見ているページの索引（0 始まり）。表示は 1 始まりへ直す。
    private(set) var currentIndex = 0
    /// 総ページ数。**0 は「まだ出せない」**を意味する（文書が無い／面がまだ組み上がって
    /// いない）。表示するかどうかはこの事実で決め、ページ矩形が空かどうかのような
    /// データの形では決めない。
    private(set) var pageCount = 0

    /// ページ番号を打ち込んでいる最中か（TASK-578.2）。
    private(set) var isEditing = false
    /// 入力中の文字列。**View の `@State` ではなくここに置く。** SwiftUI の外から
    /// 触れないと入力の検証がテストできず、受け付けない入力の扱いを固定できない。
    var draft = ""

    /// 面への橋渡し。**弱参照の口を共有する**（面を所有しない）。
    private let pdfViewProxy: PDFViewProxy
    /// 監視の後始末。**`deinit` から `@MainActor` の stored property は触れない**ので、
    /// トークンは隔離の無い箱に持たせ、その解放時に外す。外し忘れると
    /// `NotificationCenter` がブロックを持ち続け、窓を開くたびに空振りの購読が増える。
    private let observers = ObserverBox()

    init(pdfViewProxy: PDFViewProxy) {
        self.pdfViewProxy = pdfViewProxy
        observe()
    }

    /// 購読トークンを持ち、解放時に外すだけの箱（上の `observers` の doc を参照）。
    private final class ObserverBox {
        var tokens: [NSObjectProtocol] = []

        deinit {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    /// **スクロールは `NSClipView` の bounds 変更として届く。** PDFKit の
    /// `.PDFViewPageChanged` は使わない——窓へ載せてもヘッドレスでは一度も飛ばず
    /// （`currentPage` も 0 のまま、`visiblePages` も空）、守りたい対象をテストで
    /// 測れないため（実測 / TASK-578.1）。
    ///
    /// **`object:` に特定の `NSClipView` を渡さない。** PDF 面のスクロールビューは
    /// 文書の差し替えで作り直されることがあり（`ZoomingPDFView.layout()` の doc が
    /// `allowsMagnification` を毎レイアウト入れ直している理由）、インスタンスを固定して
    /// 購読すると差し替え後に**無音で更新が止まる**。すべての bounds 変更を受けて、
    /// 発火時に現在の clipView と同一かを見て弾く（比較はポインタ 1 回）。
    private func observe() {
        let centre = NotificationCenter.default
        let scrolled = NSView.boundsDidChangeNotification
        observers.tokens.append(
            centre.addObserver(forName: scrolled, object: nil, queue: .main) { [weak self] notification in
                // 同一性だけを取り出して隔離をまたぐ（`Notification` は Sendable ではない）。
                let source = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, self.isOurClipView(source) else { return }
                    self.refresh()
                }
            }
        )
        observers.tokens.append(
            centre.addObserver(forName: .PDFViewDocumentChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // 文書が変わったら編集を閉じる。PDF から別の PDF へ切り替えても
                    // View は消えないので、編集中の値が残ると古い番号で飛びうる。
                    //
                    // **`cancel()` は呼ばない（フォーカスを動かさない）。** ここは
                    // ユーザーの操作ではなく文書の差し替えで走る。面へフォーカスを
                    // 移すと、サイドバーを矢印で流し読みしている最中に PDF の行へ
                    // 来た時点で first responder を奪い、**次の矢印が一覧へ届かなく
                    // なる**（サイドバーは選択が動いた時点でそのファイルを開くため /
                    // TASK-581）。閉じるところまでがこの経路の仕事。
                    self?.endEditing()
                    self?.refresh()
                }
            }
        )
    }

    /// 面から読み直す。**保持している値は毎回捨てる**ので、面と食い違ったままにならない。
    func refresh() {
        guard let pdfView = pdfViewProxy.pdfView else {
            pageCount = 0
            currentIndex = 0
            return
        }
        pageCount = PDFSurfaceLayout.pageCount(of: pdfView)
        currentIndex = pageCount > 0 ? PDFSurfaceLayout.currentPageIndex(of: pdfView) : 0
    }

    // MARK: - ページ番号を指定してジャンプする（TASK-578.2）

    /// 入力を受け付けてジャンプ先の索引（0 始まり）へ直す。受け付けない入力は nil。
    ///
    /// **判定は入力の形ではなく、パース結果と実際の総ページ数で行う。** 「数字だけか」を
    /// 文字種で見る形にすると、全角や符号の扱いが表示の都合で揺れる。`Int` へ通して
    /// 範囲に入るかだけを見れば、総ページ数が変われば同じ文字列の可否も正しく変わる。
    static func pageJumpTarget(from text: String, pageCount: Int) -> Int? {
        // 範囲は `1 ... pageCount` を作らずに比べる。総ページ数が 0 のとき
        // （文書が無い／面がまだ組み上がっていない）に範囲の生成そのものが落ちる。
        guard let number = Int(text.trimmingCharacters(in: .whitespaces)),
              number >= 1, number <= pageCount
        else { return nil }
        return number - 1
    }

    /// 表示をクリックして編集に入る。**いま見ているページを初期値に置く**ので、
    /// 近いページへ飛ぶときに打ち直さずに済む。
    func beginEditing() {
        // **入口で読み直す。** 溜めた値で可否を決めると、通知がまだ届いていない間
        // （面を組んだ直後など）に「ページが無い」と誤判定して編集に入れない。
        refresh()
        guard pageCount > 0 else { return }
        draft = String(currentIndex + 1)
        isEditing = true
    }

    /// 入力を確定する。受け付けない入力なら**ジャンプせずに閉じるだけ**にする
    /// （常時表示の場所にエラーを出すのは過剰で、戻せば十分 / TASK-578.2 の AC #3）。
    ///
    /// **面へは `ZoomingPDFView` のメソッドを通して書く。** PDFKit の `go(to:)` を
    /// ここから直接叩くと、面への書き込み口を 1 つに保つ約束（TASK-574.1）が割れる。
    func commit() {
        defer { endEditing() }
        defer { focusSurface() }
        refresh()
        guard let target = Self.pageJumpTarget(from: draft, pageCount: pageCount) else { return }
        pdfViewProxy.pdfView?.go(toPageAt: target)
    }

    /// 入力を捨てて元の表示へ戻す（Esc）。位置は動かさない。
    ///
    /// **ユーザーが入力を閉じたときだけ呼ぶ。** 文書の差し替えで閉じる経路は
    /// `observe()` から `endEditing()` を直接呼ぶ（フォーカスを動かさないため）。
    func cancel() {
        endEditing()
        focusSurface()
    }

    /// 入力を閉じたら**面へフォーカスを移す。**
    ///
    /// 入力欄を出す前の first responder へ返す形にしていたが、実測ではそれが
    /// サイドバーのファイル一覧で、ジャンプ直後に ↓ を押すと選択が動いて
    /// **別のファイルが開いた**（TASK-578.2）。飛んだ先を読み続けられるよう、
    /// 戻し先は「いま読んでいる面」に決め打つ。
    ///
    /// **1 周待つ。** 入力欄が消えるより先に移すと、その後の View の片付けで
    /// first responder が外れる。
    private func focusSurface() {
        let surface = pdfViewProxy.pdfView
        DispatchQueue.main.async {
            guard let surface, let window = surface.window else { return }
            window.makeFirstResponder(surface)
        }
    }

    private func endEditing() {
        isEditing = false
        draft = ""
    }

    private func isOurClipView(_ source: ObjectIdentifier?) -> Bool {
        guard let source,
              let pdfView = pdfViewProxy.pdfView,
              let clipView = PDFSurfaceLayout.scrollView(in: pdfView)?.contentView
        else { return false }
        return source == ObjectIdentifier(clipView)
    }
}
