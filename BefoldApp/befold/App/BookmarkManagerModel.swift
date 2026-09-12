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
    /// ブックマークの**集合**が変わったあとに呼ぶ。開いている全ウィンドウのツールバー
    /// (ブックマークボタン)を追随させる(`GlobalDisplayBroadcaster.refreshAllToolbars`)。
    /// 別名・フォルダーの変更は集合を変えないので呼ばない。
    /// 既定値は置かない——渡し忘れると、パネルで消したのに窓のボタンが点いたままになる。
    private let onChange: @MainActor () -> Void
    /// ストアのスナップショット。`refresh()` と各操作のあとに取り直す。
    private(set) var library = BookmarkLibrary()

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

    /// 全エントリを表示名順で(フォルダーを問わない)。Delete キーの対象探しに使う。
    var entries: [BookmarkEntry] {
        library.entriesSortedByDisplayName
    }

    /// `parent` 直下の中身(フォルダーが先、エントリが後)。ツリーの各段はこれで描く。
    func children(of parent: [String]) -> BookmarkChildren {
        library.children(of: parent)
    }

    /// ストアの現在値を取り直す。パネルの外(窓の ⌘D・CLI・欠落の一括削除)で変わった分を拾うため、
    /// パネルが key になったときにも呼ぶ。
    func refresh() {
        library = store.library()
    }

    /// 別名を設定する。空なら別名なし(ファイル名表示)に戻す。
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

    // MARK: - フォルダー(成否の規則は BookmarkLibrary を参照)

    @discardableResult
    func createFolder(named name: String, in parent: [String]) -> Bool {
        defer { refresh() }
        return store.createFolder(named: name, in: parent)
    }

    @discardableResult
    func renameFolder(at path: [String], to name: String) -> Bool {
        defer { refresh() }
        return store.renameFolder(at: path, to: name)
    }

    /// 配下は親へ繰り上がるので確認は挟まない(失われるものが無い)。
    @discardableResult
    func deleteFolder(at path: [String]) -> Bool {
        defer { refresh() }
        return store.deleteFolder(at: path)
    }

    @discardableResult
    func move(_ url: URL, to folder: [String]) -> Bool {
        defer { refresh() }
        return store.move(url, toFolder: folder)
    }

    func setExpanded(_ isExpanded: Bool, for path: [String]) {
        store.setFolderExpanded(isExpanded, at: path)
        refresh()
    }
}
