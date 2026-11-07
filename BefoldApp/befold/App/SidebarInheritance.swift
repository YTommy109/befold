import AppKit
import Foundation

/// 新しい窓を開くときに、**起点の窓から引き継ぐ材料**を採取する(TASK-593.2)。
///
/// `ViewerWindowManager` から分けているのは行数の都合ではなく、ここが扱うのが
/// 「窓を開く手順」ではなく**引き継ぎの対象と条件**だからである。入力は起点の
/// `NSWindow` と「タブとして開くか」だけで、CLI のオプションは知らない。
///
/// 運ぶものが分かれているのが要点。
///
/// - `listingSeed(from:)`: 列挙の**材料**(`DirectoryListing`)と、その列挙の入力
///   (並び順・不可視ファイル)。当ててよいかの判定は `SidebarListingSeed.canApply(to:)`。
/// - `expansion(from:)`: ツリーの**展開状態**(pathKey → URL)。これは列挙の入力ではなく
///   窓ごとの表示状態(`SidebarExpansion`)なので、seed へ混ぜると `canApply(to:)` の
///   一致条件——「列挙の入力が同じか」——の意味が濁る。
///
/// 開閉は窓の現在値をそのまま読むだけで、引き継ぐのは開き先がタブのときだけ
/// (別の窓は保存値から始まる。ADR 0002「窓の状態」)。
///
/// 表示 4 値(並び順・不可視・変更のみ・レイアウト)は**ここを通らない**。あちらは
/// `SidebarDisplayOverrides` が既に持つ器で、CLI の上書きと同じ経路で窓へ届く。
@MainActor
enum SidebarInheritance {
    /// 1 回の「窓を開く」で引き継ぐものの束。**別々に持ち回らない**——引数で
    /// 並べると、経路が増えたときに片方だけ通し忘れる(`SidebarDisplayOverrides` と同じ理由)。
    struct Seed {
        /// 列挙の材料。引き継げない組み合わせなら nil。
        var listing: SidebarListingSeed?
        /// ツリーの展開状態(pathKey → URL)。
        var expansion: [String: URL]
        /// サイドバーの開閉。タブとして開かないなら nil。
        var sidebarCollapsed: Bool?

        /// 引き継ぐものが無い。起点の窓が無い経路(CLI・Finder・セッション復元)はこれ。
        static let none = Seed(listing: nil, expansion: [:], sidebarCollapsed: nil)
    }

    /// 起点の窓から引き継げるものを 1 度に採る。
    static func seed(from sourceWindow: NSWindow?, opensAsTab: Bool) -> Seed {
        Seed(
            listing: listingSeed(from: sourceWindow), expansion: expansion(from: sourceWindow),
            sidebarCollapsed: opensAsTab ? sidebarCollapsed(from: sourceWindow) : nil
        )
    }

    /// 起点ウィンドウのサイドバーが列挙済みの一覧(引き継ぎの材料)。
    /// ビューアウィンドウでない・まだ一覧が届いていないなら nil。
    static func listingSeed(from sourceWindow: NSWindow?) -> SidebarListingSeed? {
        guard let controller = viewerController(of: sourceWindow),
              controller.fileListModel.hasLoadedEntries
        else { return nil }
        let model = controller.fileListModel
        return SidebarListingSeed(
            directory: model.entriesDirectory,
            listing: controller.sidebar.lastListing,
            sortOrder: model.display.sortOrder,
            showHiddenFiles: model.display.showHiddenFiles
        )
    }

    /// 起点ウィンドウのツリー展開(pathKey → URL)。ビューアウィンドウでなければ空。
    static func expansion(from sourceWindow: NSWindow?) -> [String: URL] {
        viewerController(of: sourceWindow)?.sidebar.expandedFolderURLs ?? [:]
    }

    /// 起点の窓のサイドバー開閉。ビューア窓でなければ nil。
    static func sidebarCollapsed(from sourceWindow: NSWindow?) -> Bool? {
        viewerController(of: sourceWindow)?.sidebarCollapsible?.resolvedSidebarCollapsed
    }

    /// 起点の窓がビューア窓なら、そのコントローラ。**採取ごとに同じ判定を持たない**
    /// ようにここへ寄せる。
    private static func viewerController(of window: NSWindow?) -> ViewerWindowController? {
        window?.windowController as? ViewerWindowController
    }
}
