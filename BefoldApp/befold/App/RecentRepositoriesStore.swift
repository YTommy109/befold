import BefoldKit
import Foundation

/// 「最近使ったリポジトリ」1件分。識別情報(ルート・表示ラベル)に加えて、
/// このリポジトリで最後に開いていたタブ構成も1エントリにまとめて持つ。
/// ラベルは記録時点(record 呼び出し時)に確定させ、表示のたびに git を呼び直さない。
///
/// 将来フィールドを追加する場合は必ず optional/デフォルト値ありにすること。
/// 旧バージョンが書いた JSON を新バージョンが読む(その逆も)ため、
/// non-optional な必須フィールドを増やすと既存の保存データがデコード不能になる
/// (`pruneMissing` はデコード不能なデータを検出しても書き換えない設計だが、
/// 読み取り自体は諦めて一覧が空に見えてしまう)。
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
    ///
    /// タブは1枚ずつ閉じるため、3タブのウィンドウを閉じると
    /// [A,B,C] → [B,C] → [C] と連続で呼ばれる。素直に上書きすると最後の1枚だけが
    /// 残ってしまうので、`force` が false のときは「保存済み構成の真部分集合」への
    /// 縮小だけの書き込みを拒否する(連鎖の最初の書き込みが完全な構成を捉えている)。
    /// 同じ集合(選択タブだけの変化)や新しいパスを含む場合は従来どおり書き込む。
    /// - Parameter force: true なら部分集合でも常に上書きする。アプリ終了時の一括記録が
    ///   使い、ユーザーが実際に開いていた構成(意図的に減らしたタブも含む)を正とする。
    func updateLastTabGroup(root: URL, _ group: SessionLayout.TabGroup, force: Bool = false) {
        let path = root.normalizedPathKey
        var entries = savedEntries()
        guard let index = entries.firstIndex(where: { $0.rootPath == path }) else { return }
        if !force, let stored = entries[index].lastTabGroup,
           Set(group.paths).isStrictSubset(of: Set(stored.paths))
        {
            return
        }
        entries[index].lastTabGroup = group
        save(entries)
    }

    /// もはやディレクトリとして存在しないルート(worktree 削除など)を一覧から取り除く。
    /// 保存データがデコードできない(将来スキーマ・部分書き込み等)場合は空リストへ置き換えず、
    /// そのまま保持する(壊れたデータを空配列で上書きして履歴を失わないため)。
    /// 除外対象が無い場合も書き込みをスキップする(呼び出しごとの無駄な永続化を避ける)。
    ///
    /// エントリ数ぶんの isDirectory(stat)はアンマウント済み/応答しないネットワークマウントでは
    /// 待たされうるため、MainActor 外(Task.detached)で行う。呼び出しは起動時1回で足り、
    /// メニュー表示(menuNeedsUpdate)からは呼ばない(保存済みリストをそのまま出す)。
    func pruneMissingAsync() async {
        guard case let .decoded(entries) = loadEntries() else { return }
        let fileReader = fileReader
        let filtered = await Task.detached(priority: .utility) {
            entries.filter { fileReader.isDirectory(at: URL(fileURLWithPath: $0.rootPath)) }
        }.value
        guard filtered.count != entries.count else { return }
        save(filtered)
    }

    /// 一覧を全て消す(Clear Menu)。
    func clear() {
        save([])
    }

    /// defaults の生データを「未保存」と「デコード不能」で区別して読み込む。
    private enum LoadResult {
        case absent
        case decoded([RecentRepositoryEntry])
        case corrupted
    }

    private func loadEntries() -> LoadResult {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return .absent }
        guard let entries = try? JSONDecoder().decode([RecentRepositoryEntry].self, from: data) else {
            return .corrupted
        }
        return .decoded(entries)
    }

    /// 表示・記録用の一覧取得では、未保存/デコード不能のどちらも空扱いで構わない
    /// (record/updateLastTabGroup/entries は新規追加や表示だけで、壊れたデータの温存が問題にならないため)。
    private func savedEntries() -> [RecentRepositoryEntry] {
        guard case let .decoded(entries) = loadEntries() else { return [] }
        return entries
    }

    private func save(_ entries: [RecentRepositoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
