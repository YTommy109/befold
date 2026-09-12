/// ブックマーク管理パネルの一覧の行の識別子。`List(selection:)` と Delete キーの対象に使う。
/// フォルダーは名前列、ブックマークは正規化パスで識別する(どちらもライブラリ内で一意)。
enum BookmarkRow: Hashable {
    case folder([String])
    case bookmark(String)
}
