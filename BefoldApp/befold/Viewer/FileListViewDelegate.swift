import BefoldKit
import Foundation

/// サイドバー一覧(`FileListView`)の行操作の受け手。
///
/// 行ごとの操作(選択・移動・別の場所で開く・展開/畳み)はどれも受け手が
/// ViewerWindowController / SidebarNavigator に固定されているため、注入クロージャを
/// 1 本ずつ生やさずこのプロトコルへ畳む(`SidebarNavigatorHost` と同じ流儀)。
///
/// 表示切り替え(並び順・不可視ファイル・変更のみ・ツリー表示・スライドモード)も
/// 同じ理由でここへ畳んである(TASK-586)。**種別は `SidebarDisplayRequest` の値で
/// 表し、メソッドは 1 本に保つ**——切り替えを 1 つ足すたびにプロトコルのメソッドが
/// 増えると、再び「注入クロージャを 1 本ずつ生やす」のと同じ形に戻る。
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
    /// サイドバーヘッダーからの表示切り替え要求。種別は引数の列挙で表す。
    func fileListDidRequestDisplayChange(_ request: SidebarDisplayRequest)
}

/// サイドバーの「一覧の見せ方」の切り替え要求。
///
/// **`SidebarDisplayChange` を直に渡さない。** あちらは窓ごとに保持し既定値へ
/// 書き戻すサイドバー表示 4 値(ADR 0002「窓の状態」)の変更だけを表す。スライドモードは
/// 永続化されず、状態と同時にサイドバー幅も動かす(`SlideModeCoordinator`)ため、
/// 4 値の列挙へ混ぜると `SidebarNavigator.applyDisplayChange(_:)` が幅の面倒まで
/// 見ることになる。ここで 1 段包んで、配り先を受け手側の switch で分ける。
enum SidebarDisplayRequest: Equatable {
    /// サイドバー表示 4 値の変更。`SidebarNavigator.applyDisplayChange(_:)` へ渡る。
    case display(SidebarDisplayChange)
    /// スライドモードの反転。メニュー(⌃⌘P)と同じ `toggleSlideMode(_:)` を通る。
    case slideMode
}
