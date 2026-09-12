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
    /// ブックマークの集合が変わったあとに呼ぶ。開いている全ウィンドウのツールバー
    /// (ブックマークボタン)を追随させる(`GlobalDisplayBroadcaster.refreshAllToolbars`)。
    /// 既定値は置かない——渡し忘れると、パネルで消したのに窓のボタンが点いたままになる。
    private let onChange: @MainActor () -> Void
    /// 表示名順の一覧。`refresh()` と各操作のあとに取り直す。
    private(set) var entries: [BookmarkEntry] = []

    init(
        store: BookmarkStore,
        open: @escaping @MainActor (URL) -> Void,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.open = open
        self.onChange = onChange
        refresh()
    }

    /// ストアの現在値を取り直す。パネルの外(窓の ⌘D・CLI・欠落の一括削除)で変わった分を拾うため、
    /// パネルが key になったときにも呼ぶ。
    func refresh() {
        entries = store.library().entriesSortedByDisplayName
    }

    /// 別名を設定する。空なら別名なし(ファイル名表示)に戻す。集合は変わらないので `onChange` は呼ばない。
    func setAlias(_ alias: String, for url: URL) {
        store.setAlias(alias, for: url)
        refresh()
    }

    /// ブックマークを外す。未登録なら何もしない(`onChange` も呼ばない)。
    /// 確認は挟まない——⌘D で付け直せるので失われるものが無い。
    func remove(_ url: URL) {
        guard store.isBookmarked(url) else { return }
        store.remove(url)
        refresh()
        onChange()
    }
}
