import Foundation

/// 開いているファイルの一覧を UserDefaults に永続化し、次回起動時の状態復元に使う。
/// パスはシンボリックリンク解決後の絶対パスで正規化して保持する。
@MainActor
final class SessionStore {
    private static let defaultsKey = "SessionOpenFilePaths"

    private let defaults: UserDefaults
    /// アプリ終了処理中はウィンドウクローズを記録しない(リストが空になるのを防ぐ)。
    private var isFrozen = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 前回セッションで開いていたファイルの URL 一覧を開いた順で返す。
    func savedURLs() -> [URL] {
        savedPaths().map { URL(fileURLWithPath: $0) }
    }

    /// ファイルが開かれたことを記録する。既に記録済みの場合は順序を維持したまま何もしない。
    func noteOpened(_ url: URL) {
        let path = Self.normalize(url)
        var paths = savedPaths()
        guard !paths.contains(path) else { return }
        paths.append(path)
        defaults.set(paths, forKey: Self.defaultsKey)
    }

    /// ファイルが閉じられたことを記録する。freeze 後は無視する。
    func noteClosed(_ url: URL) {
        guard !isFrozen else { return }
        let path = Self.normalize(url)
        let paths = savedPaths().filter { $0 != path }
        defaults.set(paths, forKey: Self.defaultsKey)
    }

    /// 以降の noteClosed を無視する。アプリ終了直前に呼ぶ。
    func freeze() {
        isFrozen = true
    }

    private func savedPaths() -> [String] {
        defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    private static func normalize(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }
}
