import Foundation

/// ファイル毎に永続化する表示状態(倍率・ソース表示モード・スクロール位置)の束。
/// rename / move 時の移行をまとめて 1 呼び出しに集約し、注入経路も 1 オブジェクトへ束ねる。
@MainActor
final class PerFileStateStore {
    let zoom: ZoomStore
    let sourceMode: SourceModeStore
    let scrollPosition: ScrollPositionStore
    let sidebar: SidebarStateStore
    let windowFrame: WindowFrameStore

    /// - Parameter defaults: 各ストア(zoom / sourceMode / scrollPosition / sidebar / windowFrame)の
    ///   永続化先。本番では必ず AppDelegate が生成した単一の共有インスタンスを注入すること
    ///   (このイニシャライザ自体はテストの都合で defaults に既定値を持つが、
    ///   PerFileStateStore インスタンス自体は全ウィンドウで共有される前提)。
    init(defaults: UserDefaults = .standard) {
        zoom = ZoomStore(defaults: defaults)
        sourceMode = SourceModeStore(defaults: defaults)
        scrollPosition = ScrollPositionStore(defaults: defaults)
        sidebar = SidebarStateStore(defaults: defaults)
        windowFrame = WindowFrameStore(defaults: defaults)
    }

    /// 個別ストアを差し替えたいテスト向けの注入イニシャライザ。
    init(
        zoom: ZoomStore, sourceMode: SourceModeStore, scrollPosition: ScrollPositionStore,
        sidebar: SidebarStateStore, windowFrame: WindowFrameStore
    ) {
        self.zoom = zoom
        self.sourceMode = sourceMode
        self.scrollPosition = scrollPosition
        self.sidebar = sidebar
        self.windowFrame = windowFrame
    }

    /// ファイルの rename / move に伴い、旧パスの全状態(倍率・ソース表示モード・
    /// スクロール位置・サイドバー開閉状態・ウィンドウフレーム)を新パスへまとめて引き継ぐ。
    /// 実体は同一ファイルの改名であり、表示状態は原則保持する。
    func migrate(from oldURL: URL, to newURL: URL) {
        zoom.migrateZoom(from: oldURL, to: newURL)
        sourceMode.migrateSourceMode(from: oldURL, to: newURL)
        scrollPosition.migrateScrollPosition(from: oldURL, to: newURL)
        sidebar.migrateCollapsed(from: oldURL, to: newURL)
        windowFrame.migrateFrameDescriptor(from: oldURL, to: newURL)
    }
}
