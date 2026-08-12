import AppKit
import BefoldKit

// MARK: - Menu / Toolbar Actions and Validation

/// メインメニュー・ツールバーから来るコマンドの受け口と、その有効判定。
///
/// **@objc アクションはコントローラ自身に生えている必要がある**(NSResponder チェーンを
/// 辿って届くため)。別クラスへは移せないので、実処理はそれぞれの担当
/// (`WebViewCommandController` / `ViewerDocumentPresenter` / `ViewerDiffPresenter`)へ委譲し、
/// ここには「どのコマンドがどこへ行くか」だけを置く。
///
/// その場で組み立てるコンテキストメニューのアクションはここではなく、メニューを作る側
/// (`ViewerWindowController+References.swift`)に置く。
///
/// 有効判定(`validateMenuItem`)の対応表は `ViewerMenuValidator` にあり、ここは受け口だけ。
@MainActor
extension ViewerWindowController {
    /// View > Zoom In。HTML 直接ロード時は WKWebView の pageZoom を、それ以外は JS ズーム実装を使う。
    @objc func zoomIn(_ sender: Any?) {
        webViewCommands.zoomIn()
    }

    /// View > Zoom Out。
    @objc func zoomOut(_ sender: Any?) {
        webViewCommands.zoomOut()
    }

    /// View > Actual Size。倍率を 100% に戻す。
    @objc func resetZoom(_ sender: Any?) {
        webViewCommands.resetZoom()
    }

    /// File > Print…。WebView の描画内容を印刷する。
    @objc func printDocument(_ sender: Any?) {
        webViewCommands.printDocument(over: window)
    }

    /// Edit > 検索…。プレビュー右上の検索バーを開く。
    /// HTML ファイルの直接ロード表示中は viewer.html の JS が存在しないため無効化する
    /// (validateMenuItem 側で判定)。
    @objc func find(_ sender: Any?) {
        webViewCommands.openFind()
    }

    /// Edit > 次を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findNext(_ sender: Any?) {
        webViewCommands.findNext()
    }

    /// Edit > 前を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findPrevious(_ sender: Any?) {
        webViewCommands.findPrevious()
    }

    /// View > Toggle Line Numbers / ツールバーの行番号ボタン。行番号表示の有無を切り替える。
    @objc func toggleLineNumbers(_ sender: Any?) {
        guard capabilities.canToggleLineNumbers else { return }
        store.showLineNumbers.toggle()
        refreshToolbarState()
    }

    /// View メニュー > ソース表示トグル(⌘U)。レンダリング表示とソース表示を往復する。
    /// ⌘1〜⌘3 の「指定」に対し、こちらは「往復」で動作が違うため両方を残している。
    @objc func toggleSourceView(_ sender: Any?) {
        documentPresenter.toggleSourceView()
    }

    /// View メニュー > レンダリング / ソース / 差分(⌘1〜⌘3)。
    /// どのモードを選ぶ項目かは NSMenuItem.tag が運ぶ(項目ごとに別セレクタを生やさない)。
    @objc func selectDisplayMode(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, let mode = ViewerDisplayMode(menuItemTag: tag) else { return }
        setDisplayMode(mode)
    }

    /// View メニュー > 差分を左右に並べる(⌘\\)。インラインと左右分割を切り替える。
    @objc func toggleDiffLayout(_ sender: Any?) {
        guard capabilities.canToggleDiffLayout else { return }
        diffPresenter.toggleLayout()
        // ツールバーの差分セグメントはこの値をアイコンで映すが、view ベースのアイテムは
        // 状態変化で自動更新されない。設定はアプリ全体共有なので、自窓だけでなく
        // 全窓を再同期する(委譲先: ViewerWindowManager)。
        delegate?.viewerWindowDidToggleDiffLayout(self)
    }

    /// View > Bookmark / ツールバーのブックマークボタン。現在ファイルのブックマーク状態を切り替える。
    @objc func toggleBookmark(_ sender: Any?) {
        guard capabilities.canBookmark else { return }
        bookmarkStore.toggle(fileURL)
        refreshToolbarState()
    }

    /// 現在ファイルがブックマーク済みかどうか。ツールバー・View メニューの表示に使う。
    var isBookmarked: Bool {
        bookmarkStore.isBookmarked(fileURL)
    }

    /// View > Back。ファイル履歴を 1 つ戻る。
    @objc func goBack(_ sender: Any?) {
        navigateHistory(by: -1)
    }

    /// View > Forward。ファイル履歴を 1 つ進む。
    @objc func goForward(_ sender: Any?) {
        navigateHistory(by: 1)
    }

    /// AppKit からの有効判定要求の受け口。対応表は `ViewerMenuValidator` にある。
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        ViewerMenuValidator.validate(menuItem, source: self)
    }
}
