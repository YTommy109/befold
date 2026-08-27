import BefoldKit
import Foundation

/// "Open Recent" 履歴を UserDefaults に永続化するストア。
/// macOS 標準の Recent Documents(sharedfilelistd)はコード署名アイデンティティに
/// 紐付いており、ad-hoc 署名のリリースではアップデートのたびに別アプリ扱いとなって
/// 履歴が破棄される。メニューは自前描画のため、履歴データもアプリ側で保持する。
@MainActor
final class RecentDocumentsStore {
    private static let defaultsKey = "RecentDocumentPaths"

    private let recentPaths: PathListDefaults

    init(defaults: UserDefaults = .standard, maximumCount: Int = 25) {
        recentPaths = PathListDefaults(defaults: defaults, key: Self.defaultsKey, limit: maximumCount)
    }

    /// 履歴の URL を新しい順で返す。
    func recentURLs() -> [URL] {
        recentPaths.urls
    }

    /// ファイルが開かれたことを記録する。既存の同一パスは先頭へ移動し、
    /// 上限を超えた分は古い方から捨てる。
    func noteOpened(_ url: URL) {
        recentPaths.moveToFront(url)
    }

    /// rename / move を履歴に反映する。旧パスを取り除き、新パスを先頭に記録する。
    func noteRenamed(from oldURL: URL, to newURL: URL) {
        recentPaths.remove(oldURL)
        recentPaths.moveToFront(newURL)
    }

    /// 履歴を全て消す(Clear Menu)。空配列を保存するため、以降の seedIfNeeded は無効になる。
    func clear() {
        recentPaths.replaceAll(with: [])
    }

    /// 一度も記録がない初回起動時のみ、システム管理の履歴(移行元)を取り込む。
    func seedIfNeeded(with urls: [URL]) {
        guard !recentPaths.hasStoredValue else { return }
        recentPaths.replaceAll(withURLs: urls)
    }
}
