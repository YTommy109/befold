import AppKit
import Foundation

/// 引き継ぎの材料を持つ窓。文書タブと空タブが該当する。サイドバーを持たない窓は nil を返す。
@MainActor
protocol SidebarInheritanceSource: AnyObject {
    var inheritableSidebar: SidebarNavigator? { get }
    var sidebarCollapsible: (any SidebarCollapsible)? { get }
}

/// 文書タブの準拠も、引き継ぎの関心としてここへ置く(`ViewerMenuValidator` の準拠と同じ形)。
extension ViewerWindowController: SidebarInheritanceSource {
    var inheritableSidebar: SidebarNavigator? {
        sidebar
    }
}

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
        /// 空タブを同じ位置で文書へ置き換えるときの、空タブのサイドバーの位置。置き換えでなければ nil。
        var position: SidebarPosition?

        /// 引き継ぐものが無い。起点の窓が無い経路(CLI・Finder・セッション復元)はこれ。
        static let none = Seed(listing: nil, expansion: [:], sidebarCollapsed: nil, position: nil)
    }

    /// 起点の窓から引き継げるものを 1 度に採る。
    /// - Parameters:
    ///   - replacing: この要求で置き換える空タブ。置き換えでなければ nil。
    ///   - opening: 開く文書。空タブのサイドバーの位置を引き継げるかの判定に使う。
    static func seed(
        from sourceWindow: NSWindow?, opensAsTab: Bool, replacing blank: BlankTabWindowController?, opening url: URL?
    ) -> Seed {
        let listing = listingSeed(from: sourceWindow)
        return Seed(
            listing: listing, expansion: expansion(from: sourceWindow),
            sidebarCollapsed: opensAsTab ? sidebarCollapsed(from: sourceWindow) : nil,
            position: position(replacing: blank, opening: url, listing: listing)
        )
    }

    /// 起点ウィンドウのサイドバーが列挙済みの一覧(引き継ぎの材料)。
    /// サイドバーを持たない窓・まだ一覧が届いていないなら nil。
    static func listingSeed(from sourceWindow: NSWindow?) -> SidebarListingSeed? {
        guard let navigator = navigator(of: sourceWindow), navigator.fileListModel.hasLoadedEntries
        else { return nil }
        let model = navigator.fileListModel
        return SidebarListingSeed(
            directory: model.entriesDirectory,
            listing: navigator.lastListing,
            sortOrder: model.display.sortOrder,
            showHiddenFiles: model.display.showHiddenFiles
        )
    }

    /// 起点ウィンドウのツリー展開(pathKey → URL)。サイドバーを持たない窓なら空。
    static func expansion(from sourceWindow: NSWindow?) -> [String: URL] {
        navigator(of: sourceWindow)?.expandedFolderURLs ?? [:]
    }

    /// 起点の窓のサイドバー開閉。サイドバーを持たない窓なら nil。
    static func sidebarCollapsed(from sourceWindow: NSWindow?) -> Bool? {
        source(of: sourceWindow)?.sidebarCollapsible?.resolvedSidebarCollapsed
    }

    /// 空タブを置き換えるときのサイドバーの位置。
    ///
    /// 文書タブはサイドバーの行を選んでも、選んだファイルが今の一覧から選べる限り表示中のフォルダを
    /// 動かさない(TASK-465)。空タブを挟んだだけで、ツリーのルートが選んだファイルの親へ移って
    /// 展開が消えないよう、同じ規則で引き継ぐ(TASK-914)。
    ///
    /// 位置は一覧の引き継ぎ(`listing`)のフォルダから作り、一覧を引き継げないなら位置も引き継がない。
    /// 位置だけを引き継ぐと展開が落ち、閉じたツリーの中で選んだファイルが見えなくなる。
    private static func position(
        replacing blank: BlankTabWindowController?, opening url: URL?, listing: SidebarListingSeed?
    ) -> SidebarPosition? {
        guard let url, let listing, let model = blank?.inheritableSidebar?.fileListModel else { return nil }
        guard listing.directory.normalizedPathKey == model.currentDirectory.normalizedPathKey else { return nil }
        guard model.isReachableInCurrentListing(url) else { return nil }
        return SidebarPosition(currentDirectory: listing.directory, rootDirectory: model.rootDirectory)
    }

    /// 起点の窓のサイドバーが見ているフォルダ。サイドバーを持たない窓なら nil。
    static func currentDirectory(of sourceWindow: NSWindow?) -> URL? {
        navigator(of: sourceWindow)?.fileListModel.currentDirectory
    }

    /// **採取ごとに同じ判定を持たない**ようにここへ寄せる。
    private static func source(of window: NSWindow?) -> (any SidebarInheritanceSource)? {
        window?.windowController as? any SidebarInheritanceSource
    }

    private static func navigator(of window: NSWindow?) -> SidebarNavigator? {
        source(of: window)?.inheritableSidebar
    }
}

/// サイドバーが表示しているフォルダと、その窓でこれまでに到達した最上位のフォルダ。
struct SidebarPosition {
    let currentDirectory: URL
    let rootDirectory: URL
}
