import BefoldKit
import Foundation

/// ブックマーク管理パネル(`BookmarkManagerView`)の状態。`BookmarkStore` のスナップショットを持ち、
/// 各操作はストアへ書いてから取り直す(ビューはこの値だけを描く)。
///
/// ストアは既定値なしで受ける。アプリ全体で 1 個の `AppStores.bookmarkStore` 以外を渡すと、
/// パネルの変更が窓側(⌘D・ツールバー)と食い違う(TASK-319 と同型)。
@MainActor
@Observable
final class BookmarkManagerModel {
    private let store: BookmarkStore
    /// 行のダブルクリックで開く。`DocumentOpener.openViewer`(開く唯一の入口)へつなぐ。
    let open: @MainActor (URL) -> Void
    /// 表示名順の一覧。`refresh()` と各操作のあとに取り直す。
    private(set) var entries: [BookmarkEntry] = []

    init(store: BookmarkStore, open: @escaping @MainActor (URL) -> Void) {
        self.store = store
        self.open = open
        refresh()
    }

    /// ストアの現在値を取り直す。パネルの外(窓の ⌘D・CLI)で変わった分を拾うため、
    /// パネルが key になったときにも呼ぶ。
    func refresh() {
        entries = store.library().entriesSortedByDisplayName
    }

    /// 別名を設定する。空なら別名なし(ファイル名表示)に戻す。
    func setAlias(_ alias: String, for url: URL) {
        store.setAlias(alias, for: url)
        refresh()
    }
}
