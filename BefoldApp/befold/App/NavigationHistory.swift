import BefoldKit
import Foundation

/// 履歴エントリを記録した時点で **サイドバーが提示していた対象**。
///
/// 「開いている文書(`HistoryEntry.file`)」とは別物であることが要点。フォルダー行を
/// 選んで一覧を出している間も文書は開いたままなので、2 つは同時に別の URL を指す。
/// 復元時にどちらを提示すべきかは文書側からは決まらない。
///
/// 持つのは生の選択 URL ではなく **記録時の `FileListModel.previewTarget` から起こした
/// 事実**。「選択が file と違えばフォルダーだったのだろう」という推論に頼ると、提示種別を
/// 知りたい読み手(履歴メニューのラベル)が選択の中身を解釈し直すことになる(TASK-468)。
enum HistoryPresentation {
    /// ファイルを提示していた。URL はそのとき選択していた行(通常 `HistoryEntry.file` と同じ)。
    case file(URL)
    /// フォルダー一覧を提示していた。URL は選択していたフォルダー行。
    /// 選択を消して現在ディレクトリ自身の一覧を出していたときは nil。
    case folder(URL?)

    /// 復元時に選択へ書き戻す URL。**復元はこの値をそのまま書くだけ**で、
    /// 「開いているファイルの親を探す」等のヒューリスティックを挟まない。
    var selectionURL: URL? {
        switch self {
        case let .file(url): url
        case let .folder(url): url
        }
    }

    /// 提示種別と選択の正規化キーが一致するか。`HistoryEntry` の等価判定に使う。
    /// 種別が違えば選択が同じでも別のエントリ(同じフォルダーを「開いた」と「一覧で選んだ」)。
    func isSamePresentation(as other: HistoryPresentation) -> Bool {
        switch (self, other) {
        case let (.file(lhs), .file(rhs)):
            lhs.normalizedPathKey == rhs.normalizedPathKey
        case let (.folder(lhs), .folder(rhs)):
            lhs?.normalizedPathKey == rhs?.normalizedPathKey
        default:
            false
        }
    }

    /// 選択が `oldKey` を指していたら `newURL` へ差し替える(rename 追随)。
    func remapping(matching oldKey: String, to newURL: URL) -> HistoryPresentation {
        guard selectionURL?.normalizedPathKey == oldKey else { return self }
        switch self {
        case .file: return .file(newURL)
        case .folder: return .folder(newURL)
        }
    }
}

/// 戻る/進む履歴の 1 エントリ。表示ディレクトリ・表示ファイル・提示対象のスナップショット。
struct HistoryEntry: Equatable {
    let directory: URL
    let file: URL?
    /// 記録時にサイドバーが提示していた対象。**既定値を持たせないこと。**
    /// 渡し忘れがコンパイルエラーにならないと、提示対象を落としたエントリが静かに
    /// 積まれ、復元がまたファイル前提へ戻る(TASK-468 で直したのがその状態)。
    let presentation: HistoryPresentation

    /// 提示対象も等価判定に含める。含めないと「同じディレクトリで同じ文書を開いたまま
    /// フォルダー一覧へ切り替えた」エントリが重複とみなされて捨てられ、履歴に
    /// フォルダー提示が残らない。
    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.directory.normalizedPathKey == rhs.directory.normalizedPathKey
            && lhs.file?.normalizedPathKey == rhs.file?.normalizedPathKey
            && lhs.presentation.isSamePresentation(as: rhs.presentation)
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

    /// rename/move 時に履歴内の該当 URL（directory/file とも）を差し替える（陳腐化防止）。
    /// リマップにより隣接エントリが同一になった場合は重複を除去する。
    func renameOccurred(from oldURL: URL, to newURL: URL) {
        let oldFileKey = oldURL.normalizedPathKey
        let oldDirKey = oldURL.deletingLastPathComponent().normalizedPathKey
        let newDir = newURL.deletingLastPathComponent()
        entries = entries.map { entry in
            guard entry.file?.normalizedPathKey == oldFileKey else { return entry }
            let dirMatch = entry.directory.normalizedPathKey == oldDirKey
            return HistoryEntry(
                directory: dirMatch ? newDir : entry.directory,
                file: newURL,
                presentation: entry.presentation.remapping(matching: oldFileKey, to: newURL)
            )
        }
        deduplicateAdjacentEntries()
    }

    /// 隣接する同一エントリを除去し、currentIndex を調整する。
    /// 「生き残る index の集合」を先に決め、新しい entries も新しい currentIndex も
    /// そこから導く(除去とインデックス補正を同じループで絡ませない)。
    private func deduplicateAdjacentEntries() {
        let surviving = entries.indices.filter { index in
            index == 0 || entries[index] != entries[index - 1]
        }
        // 現在位置は「自分以前に生き残った数 - 1」へ移る。
        let keptUpToCurrent = surviving.count { $0 <= currentIndex }

        entries = surviving.map { entries[$0] }
        currentIndex = max(0, min(keptUpToCurrent - 1, entries.count - 1))
    }
}
