import BefoldKit
import Foundation

/// 「開けなくなったブックマーク」をユーザーの明示操作で取り除く経路。
///
/// 設計上の約束が 2 つある。どちらも `BookmarksMenuController` 側では担保できないため
/// ここへ集約している。
///
///   - **存在確認(stat)はメニュー表示では行わない。** アンマウント済み/応答しない
///     ネットワークマウントでは stat が待たされるため、`RecentRepositoriesStore.pruneMissingAsync`
///     と同じく MainActor 外(`withBlockingWork`)へ逃がし、ユーザーがこの経路を選んだときだけ走らせる。
///     `BookmarksMenuController` に `FileReading` を渡していないのは、メニュー構築時に
///     stat する実装を書けなくするため(規約でなく構造で縛る)。
///   - **ユーザーの承認なしには消さない。** 消すのは確認ダイアログで提示した URL だけで、
///     承認後に欠落集合を取り直すことはしない(提示していないものが巻き添えで消えない)。
@MainActor
final class MissingBookmarksPruner {
    private let bookmarkStore: BookmarkStore
    private let fileReader: any FileReading
    /// 欠落したブックマークの一覧を提示し、取り除いてよいかを問う。true なら実行する。
    private let confirmRemoval: ([URL]) -> Bool
    /// 欠落が 1 件も無かったことを伝える。「押しても何も起きない」と区別するために要る。
    private let reportNoneMissing: () -> Void
    /// 走行中の再入を防ぐ。stat の完了を待つ間もメニューは選び直せるため、
    /// これが無いと確認ダイアログが二重に出る。
    private var isPruning = false

    init(
        bookmarkStore: BookmarkStore,
        fileReader: any FileReading = DefaultFileReader(),
        confirmRemoval: @escaping ([URL]) -> Bool = { MissingBookmarksAlerts.confirmRemoval(of: $0) },
        reportNoneMissing: @escaping () -> Void = { MissingBookmarksAlerts.reportNoneMissing() }
    ) {
        self.bookmarkStore = bookmarkStore
        self.fileReader = fileReader
        self.confirmRemoval = confirmRemoval
        self.reportNoneMissing = reportNoneMissing
    }

    /// 欠落したブックマークを洗い出し、ユーザーが承認したものだけを取り除く。
    func pruneMissingBookmarks() async {
        guard !isPruning else { return }
        isPruning = true
        defer { isPruning = false }

        let urls = bookmarkStore.bookmarkedURLs()
        let fileReader = fileReader
        let missing = await withBlockingWork {
            Self.missingURLs(among: urls, fileReader: fileReader)
        }

        guard !missing.isEmpty else {
            reportNoneMissing()
            return
        }
        guard confirmRemoval(missing) else { return }
        bookmarkStore.removeAll(missing)
    }

    /// 存在しない URL だけを保存順のまま返す。MainActor 外から呼ぶ想定の純粋関数。
    nonisolated static func missingURLs(among urls: [URL], fileReader: any FileReading) -> [URL] {
        urls.filter { !fileReader.fileExists(at: $0) }
    }
}
