import BefoldKit
import Foundation

/// "Open Recent" 履歴を UserDefaults に永続化するストア。
/// macOS 標準の Recent Documents(sharedfilelistd)はコード署名アイデンティティに
/// 紐付いており、ad-hoc 署名のリリースではアップデートのたびに別アプリ扱いとなって
/// 履歴が破棄される。メニューは自前描画のため、履歴データもアプリ側で保持する。
@MainActor
final class RecentDocumentsStore {
    private static let defaultsKey = "RecentDocumentPaths"

    private let defaults: UserDefaults
    private let maximumCount: Int

    init(defaults: UserDefaults = .standard, maximumCount: Int = 10) {
        self.defaults = defaults
        self.maximumCount = maximumCount
    }

    /// 履歴の URL を新しい順で返す。
    func recentURLs() -> [URL] {
        savedPaths().map { URL(fileURLWithPath: $0) }
    }

    /// ファイルが開かれたことを記録する。既存の同一パスは先頭へ移動し、
    /// 上限を超えた分は古い方から捨てる。
    func noteOpened(_ url: URL) {
        let path = url.normalizedPathKey
        var paths = savedPaths().filter { $0 != path }
        paths.insert(path, at: 0)
        save(paths)
    }

    /// rename / move を履歴に反映する。旧パスを取り除き、新パスを先頭に記録する。
    func noteRenamed(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.normalizedPathKey
        save(savedPaths().filter { $0 != oldPath })
        noteOpened(newURL)
    }

    /// 履歴を全て消す(Clear Menu)。空配列を保存するため、以降の seedIfNeeded は無効になる。
    func clear() {
        save([])
    }

    /// 一度も記録がない初回起動時のみ、システム管理の履歴(移行元)を取り込む。
    func seedIfNeeded(with urls: [URL]) {
        guard defaults.object(forKey: Self.defaultsKey) == nil else { return }
        save(urls.map(\.normalizedPathKey))
    }

    private func savedPaths() -> [String] {
        defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    private func save(_ paths: [String]) {
        defaults.set(Array(paths.prefix(maximumCount)), forKey: Self.defaultsKey)
    }
}
