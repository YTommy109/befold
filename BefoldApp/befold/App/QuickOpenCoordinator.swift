import AppKit
import BefoldKit

/// Quick Open(⌘P)のアプリ側配線。パネルの生存を持ち、候補源をその時点のアプリ状態から
/// 組み立て、決定された URL の開き先を決める。
///
/// 候補の絞り込みそのものは `QuickOpenModel` 以下が持つ。ここはアプリ状態との接続だけを担う。
@MainActor
final class QuickOpenCoordinator {
    private let stores: AppStores
    private let gitIndex: any GitFileIndexing
    private let activeViewer: ActiveViewerProvider.Provide
    private let openInNewWindow: @MainActor (URL) -> Void
    private lazy var panelController = QuickOpenPanelController(
        makeEnvironment: { [weak self] in self?.makeEnvironment() },
        onOpen: { [weak self] url in self?.open(url) }
    )

    /// - Parameters:
    ///   - gitIndex: ウィンドウと共有する git 追跡ファイルの索引。パネルを開くたびに
    ///     `git ls-files` をやり直さないため、必ず共有インスタンスを渡す(既定値は持たせない)。
    ///   - openInNewWindow: 開くべきビューアウィンドウが 1 枚も無いときの開き先。
    init(
        stores: AppStores,
        gitIndex: any GitFileIndexing,
        activeViewer: @escaping ActiveViewerProvider.Provide,
        openInNewWindow: @escaping @MainActor (URL) -> Void
    ) {
        self.stores = stores
        self.gitIndex = gitIndex
        self.activeViewer = activeViewer
        self.openInNewWindow = openInNewWindow
    }

    /// File > Quick Open(⌘P)。パス入力と fuzzy 検索のパネルを開閉する。
    func toggle() {
        panelController.toggle()
    }

    /// パネルを開いた時点のアプリ状態から候補源を組み立てる。
    /// 索引はウィンドウと共有し、パネルを開くたびに `git ls-files` をやり直さない。
    private func makeEnvironment() -> AppQuickOpenEnvironment {
        // パネルは canBecomeMain=false のため、表示中でも mainWindow は元のビューアの
        // まま。専用の状態を持たず activeViewer から都度引く。
        let currentFileURL = activeViewer()?.fileURL
        if let currentFileURL {
            gitIndex.warm(forFileAt: currentFileURL)
        }
        return AppQuickOpenEnvironment(
            gitIndex: gitIndex,
            recentDocumentsStore: stores.recentDocumentsStore,
            bookmarkStore: stores.bookmarkStore,
            sidebarDisplayPreference: stores.sidebarDisplayPreference,
            currentFileURL: currentFileURL
        )
    }

    /// Quick Open の決定先を開く。決定時点で操作対象のビューアウィンドウがあればそこで
    /// 切り替え、無ければ(全ウィンドウを閉じた場合など)新規ウィンドウを開く。
    /// 決定経路(onOpen)はパネルを畳んでから呼ばれるため、mainWindow は残存ビューアを指す。
    private func open(_ url: URL) {
        guard let controller = activeViewer() else {
            openInNewWindow(url)
            return
        }
        controller.focusWindow()
        controller.switchFile(to: url)
    }
}
