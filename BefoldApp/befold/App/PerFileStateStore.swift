import Foundation

/// ファイル毎に**永続化する**表示状態(倍率・サイドバー開閉・ウィンドウフレーム)の束。
/// rename / move 時の移行をまとめて 1 呼び出しに集約し、注入経路も 1 オブジェクトへ束ねる。
///
/// ここに入るのは**内容に依存しないユーザーの意図**だけ。表示中の位置に依存する状態
/// (スクロール位置・表示モード)は窓の生存期間だけの記憶で、`WindowPresentationMemory`
/// が持つ(TASK-565)。
@MainActor
final class PerFileStateStore {
    let zoom: ZoomStore
    let sidebar: SidebarStateStore
    let windowFrame: WindowFrameStore

    /// - Parameter defaults: 各ストア(zoom / sidebar / windowFrame)の
    ///   永続化先。本番では必ず AppDelegate が生成した単一の共有インスタンスを注入すること
    ///   (このイニシャライザ自体はテストの都合で defaults に既定値を持つが、
    ///   PerFileStateStore インスタンス自体は全ウィンドウで共有される前提)。
    init(defaults: UserDefaults = .standard) {
        zoom = ZoomStore(defaults: defaults)
        sidebar = SidebarStateStore(defaults: defaults)
        windowFrame = WindowFrameStore(defaults: defaults)
    }

    /// 個別ストアを差し替えたいテスト向けの注入イニシャライザ。
    init(zoom: ZoomStore, sidebar: SidebarStateStore, windowFrame: WindowFrameStore) {
        self.zoom = zoom
        self.sidebar = sidebar
        self.windowFrame = windowFrame
    }

    /// ファイルの rename / move に伴い、旧パスの永続表示状態(倍率・サイドバー開閉状態・
    /// ウィンドウフレーム)を新パスへまとめて引き継ぐ。
    /// 実体は同一ファイルの改名であり、表示状態は原則保持する。
    /// 窓の記憶側の引き継ぎは `ViewerDocumentPresenter.migratePresentationMemory` が行う。
    func migrate(from oldURL: URL, to newURL: URL) {
        zoom.migrateZoom(from: oldURL, to: newURL)
        sidebar.migrateCollapsed(from: oldURL, to: newURL)
        windowFrame.migrateFrameDescriptor(from: oldURL, to: newURL)
    }
}
