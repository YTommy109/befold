import BefoldKit
import Foundation

/// サイドバー一覧(`FileListView`)の行操作の受け手。
///
/// 行ごとの操作(選択・移動・別の場所で開く・展開/畳み)はどれも受け手が
/// ViewerWindowController / SidebarNavigator に固定されているため、注入クロージャを
/// 1 本ずつ生やさずこのプロトコルへ畳む(`SidebarNavigatorHost` と同じ流儀)。
///
/// **既定実装は置かない。** 「ドリルダウン表示では展開が無い」という都合で
/// optional にすると、ツリー表示側の配線漏れがコンパイル時に落ちなくなる。
/// 表示モードによる出し分けは呼び出し側(`SidebarKeyAction`)が既に持っている。
@MainActor
protocol FileListViewDelegate: AnyObject {
    /// 行の選択が確定し、それがファイルだった。表示を追従させる。
    func fileListDidSelectFile(_ url: URL)
    /// フォルダー行へ降りる / 上位フォルダーへ戻る。一覧のルートが動く。
    func fileListDidRequestNavigation(to url: URL)
    /// 選択行を別のタブ/ウィンドウで開く。開き先は disposition で受ける
    /// (開き先を増やしてもメソッドが増えない)。
    func fileListDidRequestOpenElsewhere(_ url: URL, disposition: OpenDisposition)
    /// ツリー表示でフォルダ行を展開する。実際の列挙と行の組み直しは
    /// `SidebarNavigator.expandFolder` が行う。
    func fileListDidRequestExpand(_ entry: FileListEntry)
    /// ツリー表示でフォルダ行を畳む。
    func fileListDidRequestCollapse(_ entry: FileListEntry)
}
