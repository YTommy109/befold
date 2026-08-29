import BefoldKit
import Foundation

/// **いまこの窓が提示している文書の URL** を、rename / switch による書き換えごしに
/// 参照するための共有参照。
///
/// URL の唯一の保持先は `ViewerStore.currentURL` のままで、この型は値を複製しない
/// （導出しかしない）。窓の子（`ViewerDocumentPresenter` / `WebViewCommandController`）が
/// 同じ 1 個を受け取ることで、「旧 URL を捕捉しない」という制約をクロージャではなく
/// 構造で満たす。`docs/dev/rules/product-code.md`「クロージャバンドルが 3 つを超えたら
/// delegate プロトコルを検討する」が名指しした**再束縛のためのクロージャ**がこれで消え、
/// 両方の子が注入クロージャ 3 個へ収まる。
@MainActor
final class CurrentDocumentRef {
    private let store: ViewerStore
    /// store がまだ URL を持たない init 直後の一瞬を型的に埋めるブートストラップ定数。
    /// rename / switch では更新しない（更新するのは store 側だけ）。
    private let initialURL: URL

    init(store: ViewerStore, initialURL: URL) {
        self.store = store
        self.initialURL = initialURL
    }

    var url: URL {
        store.currentURL ?? initialURL
    }

    /// **描画が確定した**種別。`url` から `FileType(url:)` で導いた値とは別物で、
    /// こちらは読み込みが着地して初めて動く。
    ///
    /// `url`(= `ViewerStore.pendingURL`)は `openFile` の入口で同期的に進むのに対し、
    /// 内容と種別は `ViewerContentState.applyDisplayState` が同時に確定させる。
    /// **いま画面に出ている面**を選ぶ判断はこちらを見ること(`DocumentSurfaces.operating(on:)`)。
    /// `url` から導くと、切替直後に「画面には旧ファイルが出ているのに命令は新しい面へ飛ぶ」
    /// 区間ができる。
    var renderedFileType: FileType {
        store.contentState.fileType
    }
}
