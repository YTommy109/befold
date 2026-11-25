import Foundation

/// 本文の領域が提示している対象。ファイルなら文書の描画面、フォルダーなら
/// `FolderListingView`(その URL 直下の一覧)を出す。
///
/// 文書の URL はここに持たない。窓の現在 URL(`ViewerStore`)と二重にしないため。
enum PreviewTarget: Equatable {
    case file
    case folder(URL)

    /// フォルダー表示のときの対象ディレクトリ。ViewerContentView は
    /// 描画面を常駐させたまま一覧を重ねるため、switch ではなくこの値で分岐する。
    var folderURL: URL? {
        guard case let .folder(url) = self else { return nil }
        return url
    }
}

/// 窓が本文に何を出すかの**意図**(ADR 0013)。本文の提示はこの値だけから決まる。
///
/// **書いてよいのは、利用者の操作を受けた入口だけ**——ファイルを開く・フォルダーを選ぶ・
/// フォルダーに入る・履歴を再生する。書き手はすべて `ViewerWindowController` 側にある。
/// サイドバーの選択・一覧の行・展開の状態から導かない。かつての導出
/// (`PreviewTargetResolver`)は、行が非同期に届くまでの間「選択が一覧に無い」を
/// フォルダー提示と取り違え、ファイルを開いた直後の本文に一覧を重ねていた
/// (TASK-445 / TASK-468 / GitHub #794)。
///
/// **サイドバー側の型(`SidebarNavigator` とその協力型・`FileListModel`)へこのインスタンスを
/// 渡してはならない。** サイドバーの同期処理(一覧の取り直し・展開・レイアウト切り替え)が
/// 意図を書ける形になると、上の取り違えがそのまま戻る。サイドバーが提示を知る必要がある
/// 場面(履歴の記録)は `SidebarNavigatorHost.presentedTarget` の読み取りだけで足りる。
///
/// 窓は必ず文書を開いて生成されるため、初期値は `.file`。「まだ分からない」状態は無い。
@MainActor
@Observable
final class PresentationIntent {
    private(set) var target: PreviewTarget = .file

    /// 意図が変わったときに呼ばれる。ツールバーの view ベースアイテムは validate を
    /// 通らないため、ここを再同期の契機にする(ADR 0002)。
    @ObservationIgnored var onChange: (() -> Void)?

    /// 意図を書く。同じ値なら何もしない(再同期を増やさない)。
    func present(_ newTarget: PreviewTarget) {
        guard newTarget != target else { return }
        target = newTarget
        onChange?()
    }
}
