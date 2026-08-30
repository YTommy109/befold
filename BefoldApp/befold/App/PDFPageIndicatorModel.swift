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
                MainActor.assumeIsolated { self?.refresh() }
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

    private func isOurClipView(_ source: ObjectIdentifier?) -> Bool {
        guard let source,
              let pdfView = pdfViewProxy.pdfView,
              let clipView = PDFSurfaceLayout.scrollView(in: pdfView)?.contentView
        else { return false }
        return source == ObjectIdentifier(clipView)
    }
}
