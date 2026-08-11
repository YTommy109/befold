import AppKit

/// 「いま操作対象になっているビューアウィンドウ」を引く手続きの定義点。
///
/// この判断は AppDelegate 本体・Quick Open・ファイル選択パネルの 3 者が必要とする。
/// 各自が `NSApp.mainWindow` を読む形にすると、下に書いた不変条件が 3 箇所へ複製され、
/// どれか 1 つが別の求め方(keyWindow など)に変わっても他が気づけない。求め方はここだけに置き、
/// 利用側へは `Provide` を注入する(テストから差し替えられる形も同時に得られる)。
enum ActiveViewerProvider {
    /// 現在のビューアウィンドウを返す手続き。無ければ nil。
    typealias Provide = @MainActor () -> ViewerWindowController?

    /// Quick Open パネル(`NSPanel`, `canBecomeMain = false`)がキーを奪っている間も
    /// `NSApp.mainWindow` は元のビューアウィンドウを指し続けるため、パネル表示中でも
    /// 正しい元ウィンドウを引ける。元ウィンドウが閉じられていれば残存ウィンドウを返す。
    @MainActor
    static func fromMainWindow() -> ViewerWindowController? {
        NSApp.mainWindow?.windowController as? ViewerWindowController
    }
}
