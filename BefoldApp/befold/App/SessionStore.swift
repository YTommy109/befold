import BefoldKit
import Foundation

/// 終了時のウィンドウ/タブ構成。groups はウィンドウ(タブグループ)の前面からの並び、
/// 各グループの paths はタブの並び順(正規化パス)。
struct SessionLayout: Codable, Equatable {
    struct TabGroup: Codable, Equatable {
        /// タブの並び順(normalizedPathKey)
        var paths: [String]
        /// このグループで選択されていたタブ
        var selectedPath: String?
    }

    /// ウィンドウ(タブグループ)の並び
    var groups: [TabGroup]

    /// 存在するパスだけに絞り込む。空になったグループは取り除き、
    /// 選択タブが消えた場合はグループ先頭で代替する。
    func filtered(to availablePaths: Set<String>) -> SessionLayout {
        let filteredGroups = groups.compactMap { group -> TabGroup? in
            let paths = group.paths.filter { availablePaths.contains($0) }
            guard !paths.isEmpty else { return nil }
            let selectedPath = group.selectedPath.flatMap { paths.contains($0) ? $0 : nil } ?? paths.first
            return TabGroup(paths: paths, selectedPath: selectedPath)
        }
        return SessionLayout(groups: filteredGroups)
    }
}

/// 開いているファイルの一覧を UserDefaults に永続化し、次回起動時の状態復元に使う。
/// パスはシンボリックリンク解決後の絶対パスで正規化して保持する。
@MainActor
final class SessionStore {
    private static let defaultsKey = "SessionOpenFilePaths"
    private static let layoutKey = "SessionLayout"
    private static let activeKey = "SessionActiveFilePath"

    private let defaults: UserDefaults
    private let openFilePaths: PathListDefaults
    /// アプリ終了処理中はウィンドウクローズを記録しない(リストが空になるのを防ぐ)。
    private var isFrozen = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openFilePaths = PathListDefaults(defaults: defaults, key: Self.defaultsKey)
    }

    /// 前回セッションで開いていたファイルの URL 一覧を開いた順で返す。
    func savedURLs() -> [URL] {
        openFilePaths.urls
    }

    /// ファイルが開かれたことを記録する。既に記録済みの場合は順序を維持したまま何もしない。
    func noteOpened(_ url: URL) {
        openFilePaths.appendIfAbsent(url)
    }

    /// ファイルが閉じられたことを記録する。freeze 後は無視する。
    /// 閉じたファイルがアクティブ記録と一致する場合は記録もクリアする。
    func noteClosed(_ url: URL) {
        guard !isFrozen else { return }
        openFilePaths.remove(url)
        if savedActivePath() == url.normalizedPathKey {
            defaults.removeObject(forKey: Self.activeKey)
        }
    }

    /// 以降の noteClosed を無視する。アプリ終了直前に呼ぶ。
    func freeze() {
        isFrozen = true
    }

    /// 終了時のウィンドウ/タブ構成を保存する。
    func saveLayout(_ layout: SessionLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Self.layoutKey)
    }

    /// 保存済みのウィンドウ/タブ構成を返す。未保存・パース不能・空の場合は nil(フォールバック用)。
    func savedLayout() -> SessionLayout? {
        guard let data = defaults.data(forKey: Self.layoutKey),
              let layout = try? JSONDecoder().decode(SessionLayout.self, from: data),
              !layout.groups.isEmpty
        else { return nil }
        return layout
    }

    /// アクティブ(キーウィンドウ)になったファイルを記録する。freeze 後は無視する
    /// (終了処理中のウィンドウクローズでキーが移っても確定値を上書きしない)。
    func noteActivated(_ url: URL) {
        guard !isFrozen else { return }
        defaults.set(url.normalizedPathKey, forKey: Self.activeKey)
    }

    /// 前回アクティブだったファイルの正規化パスを返す。
    func savedActivePath() -> String? {
        defaults.string(forKey: Self.activeKey)
    }

    /// rename / move をセッション記録に反映する。
    /// アクティブ記録と保存済みレイアウト内の旧パスを新パスへ書き換える。
    /// 開いているファイル一覧の付け替えは従来どおり noteClosed / noteOpened で行う。
    func noteRenamed(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.normalizedPathKey
        let newPath = newURL.normalizedPathKey
        guard oldPath != newPath else { return }

        if savedActivePath() == oldPath {
            defaults.set(newPath, forKey: Self.activeKey)
        }
        guard let layout = savedLayout() else { return }
        let renamed = layout.groups.map { group in
            SessionLayout.TabGroup(
                paths: group.paths.map { $0 == oldPath ? newPath : $0 },
                selectedPath: group.selectedPath == oldPath ? newPath : group.selectedPath
            )
        }
        saveLayout(SessionLayout(groups: renamed))
    }
}
