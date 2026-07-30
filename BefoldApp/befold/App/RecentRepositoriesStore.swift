import BefoldKit
import Foundation

/// 「最近使ったリポジトリ」1件分。識別情報(ルート・表示ラベル)に加えて、
/// このリポジトリで最後に開いていたタブ構成も1エントリにまとめて持つ。
/// ラベルは記録時点(record 呼び出し時)に確定させ、表示のたびに git を呼び直さない。
struct RecentRepositoryEntry: Codable, Equatable {
    var rootPath: String
    var label: String
    var lastTabGroup: SessionLayout.TabGroup?

    var root: URL {
        URL(fileURLWithPath: rootPath)
    }
}

/// "Recent Repositories" 履歴を UserDefaults に永続化するストア。
/// RecentDocumentsStore と同じ理由(ad-hoc 署名では sharedfilelistd 由来の履歴が
/// アップデートのたびに失われる)で、自前に持つ。
@MainActor
final class RecentRepositoriesStore {
    private static let defaultsKey = "RecentRepositories"

    private let defaults: UserDefaults
    private let maximumCount: Int
    private let fileReader: any FileReading

    init(
        defaults: UserDefaults = .standard, maximumCount: Int = 10,
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.defaults = defaults
        self.maximumCount = maximumCount
        self.fileReader = fileReader
    }

    /// 一覧を最終利用順(新しい順)で返す。
    func entries() -> [RecentRepositoryEntry] {
        savedEntries()
    }

    /// リポジトリが開かれたことを記録する。既存の同一ルートは先頭へ移動し
    /// (lastTabGroup は保持したまま)、無ければ lastTabGroup なしで新規追加する。
    /// 上限を超えた分は古い方から捨てる。
    func record(root: URL, label: String) {
        let path = root.normalizedPathKey
        var entries = savedEntries()
        let existingLastTabGroup = entries.first { $0.rootPath == path }?.lastTabGroup
        entries.removeAll { $0.rootPath == path }
        entries.insert(
            RecentRepositoryEntry(rootPath: path, label: label, lastTabGroup: existingLastTabGroup), at: 0
        )
        save(Array(entries.prefix(maximumCount)))
    }

    /// 該当ルートのエントリの lastTabGroup のみ上書きする(並び順は変えない)。
    /// 記録されていないルートを渡された場合は何もしない。
    func updateLastTabGroup(root: URL, _ group: SessionLayout.TabGroup) {
        let path = root.normalizedPathKey
        var entries = savedEntries()
        guard let index = entries.firstIndex(where: { $0.rootPath == path }) else { return }
        entries[index].lastTabGroup = group
        save(entries)
    }

    /// もはやディレクトリとして存在しないルート(worktree 削除など)を一覧から取り除く。
    func pruneMissing() {
        save(savedEntries().filter { fileReader.isDirectory(at: URL(fileURLWithPath: $0.rootPath)) })
    }

    /// 一覧を全て消す(Clear Menu)。
    func clear() {
        save([])
    }

    private func savedEntries() -> [RecentRepositoryEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([RecentRepositoryEntry].self, from: data)
        else { return [] }
        return entries
    }

    private func save(_ entries: [RecentRepositoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
