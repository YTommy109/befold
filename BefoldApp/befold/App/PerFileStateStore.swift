import Foundation

/// ファイル毎に永続化する表示状態(倍率・ソース表示モード・スクロール位置)の束。
/// rename / move 時の移行をまとめて 1 呼び出しに集約し、注入経路も 1 オブジェクトへ束ねる。
@MainActor
final class PerFileStateStore {
    let zoom: ZoomStore
    let sourceMode: SourceModeStore
    let scrollPosition: ScrollPositionStore

    init(defaults: UserDefaults = .standard) {
        zoom = ZoomStore(defaults: defaults)
        sourceMode = SourceModeStore(defaults: defaults)
        scrollPosition = ScrollPositionStore(defaults: defaults)
    }

    /// 個別ストアを差し替えたいテスト向けの注入イニシャライザ。
    init(zoom: ZoomStore, sourceMode: SourceModeStore, scrollPosition: ScrollPositionStore) {
        self.zoom = zoom
        self.sourceMode = sourceMode
        self.scrollPosition = scrollPosition
    }

    /// ファイルの rename / move に伴い、旧パスの全状態(倍率・ソース表示モード・
    /// スクロール位置)を新パスへまとめて引き継ぐ。実体は同一ファイルの改名であり、
    /// 表示状態は原則保持する。
    func migrate(from oldURL: URL, to newURL: URL) {
        zoom.migrateZoom(from: oldURL, to: newURL)
        sourceMode.migrateSourceMode(from: oldURL, to: newURL)
        scrollPosition.migrateScrollPosition(from: oldURL, to: newURL)
    }
}
