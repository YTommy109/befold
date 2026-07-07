import Foundation

/// 戻る/進む履歴の 1 エントリ。表示ディレクトリと表示ファイルのスナップショット。
struct HistoryEntry: Equatable {
    let directory: URL
    let file: URL?

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.directory.normalizedPathKey == rhs.directory.normalizedPathKey
            && lhs.file?.normalizedPathKey == rhs.file?.normalizedPathKey
    }
}

/// タブ 1 つ分の戻る/進むナビゲーション履歴。統合 1 本のスタックとして
/// ディレクトリ移動とファイル参照を時系列で保持する。永続化はしない。
@MainActor
final class NavigationHistory {
    private(set) var entries: [HistoryEntry] = []
    /// 現在地。空のときは -1。
    private(set) var currentIndex: Int = -1

    var canGoBack: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        currentIndex >= 0 && currentIndex < entries.count - 1
    }

    /// 現在エントリと同一なら何もしない（重複防止）。
    /// そうでなければ「進む」履歴を破棄して末尾に追加し、現在地を末尾へ進める。
    func push(_ entry: HistoryEntry) {
        if currentIndex >= 0, entries[currentIndex] == entry { return }
        if currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)...)
        }
        entries.append(entry)
        currentIndex = entries.count - 1
    }

    /// 現在地を offset だけ移動して移動先エントリを返す。範囲外なら nil（現在地不変）。
    func move(by offset: Int) -> HistoryEntry? {
        let target = currentIndex + offset
        guard entries.indices.contains(target) else { return nil }
        currentIndex = target
        return entries[target]
    }

    /// 戻るメニュー用。現在地の 1 つ前から先頭に向かって新しい順。
    func backEntries() -> [HistoryEntry] {
        guard currentIndex > 0 else { return [] }
        return (0 ..< currentIndex).reversed().map { entries[$0] }
    }

    /// 進むメニュー用。現在地の 1 つ後から末尾に向かって近い順。
    func forwardEntries() -> [HistoryEntry] {
        guard currentIndex >= 0, currentIndex < entries.count - 1 else { return [] }
        return ((currentIndex + 1) ..< entries.count).map { entries[$0] }
    }

    /// rename/move 時に履歴内の該当ファイル参照を新 URL へ差し替える（陳腐化防止）。
    func renameOccurred(from oldURL: URL, to newURL: URL) {
        let oldKey = oldURL.normalizedPathKey
        entries = entries.map { entry in
            guard let file = entry.file, file.normalizedPathKey == oldKey else { return entry }
            return HistoryEntry(directory: entry.directory, file: newURL)
        }
    }
}
