import AppKit
import BefoldKit

// MARK: - ReferenceResolutionHost

/// 本文中のリンク・パス参照を「開く / 見つからないと伝える / 右クリックメニューを出す」層。
///
/// 解決そのもの(索引の先読み・相対パスの解決・外部 URL の判別)は
/// `ReferenceResolutionCoordinator` が持ち、ここはその結果をウィンドウの操作へ繋ぐ。
///
/// **その場で組み立てるコンテキストメニューの @objc アクションは、メニューを作る側と同居させる。**
/// メインメニュー/ツールバー由来のアクション(`ViewerWindowController+MenuActions.swift`)と違い、
/// 項目定義・表示・実行が 1 つの流れなので、離すと `#selector` の対応が読めなくなる。
@MainActor
extension ViewerWindowController: ReferenceResolutionHost {
    /// ReferenceResolutionCoordinator が解決の基準ディレクトリを都度参照するための橋渡し。
    var referenceBaseURL: URL {
        fileURL
    }

    /// リンク/パス参照のアクティベーションを処理する。
    /// テスト(@testable import)から回帰テストとして直接呼べるよう internal にする(外部公開はしない)。
    func handleOpenReference(href: String, disposition: OpenDisposition) {
        referenceCoordinator.handleOpenReference(href: href, disposition: disposition)
    }

    /// パス参照群を解決し、実在するものだけ「書かれたパス→解決済み絶対パス」で返す(表示時解決用)。
    func resolveReferences(_ paths: [String]) async -> [String: String] {
        await referenceCoordinator.resolveReferences(paths)
    }

    /// 解決できたパス参照を、開き方(disposition)に応じてこのウィンドウ/別タブ/別ウィンドウで開く。
    func openReference(_ url: URL, disposition: OpenDisposition) {
        switch disposition {
        case .currentTab:
            switchFile(to: url)
        case .newTab, .newWindow:
            openFileElsewhere(url, disposition, window)
        }
    }

    /// 参照先が見つからないことをユーザーに知らせる。
    /// window があればシート、無ければモーダルで表示する(判定は FileNotFoundUI 側)。
    func presentReferenceNotFound(url: URL) {
        FileNotFoundUI.present(url: url, over: window)
    }

    /// リンク/パス参照の ctrl+クリック(右クリック)で NSMenu を表示する。
    /// 表示位置は JS の座標ではなく現在のマウス位置を使う(WKWebView の CSS ピクセルと
    /// NSView 座標の変換、ページズームの影響を避けるため)。
    func presentReferenceContextMenu(for url: URL, isExternal: Bool) {
        guard let contentView = window?.contentView,
              let location = window?.mouseLocationOutsideOfEventStream
        else { return }
        let menu = ReferenceContextMenu.makeMenu(
            for: url, isExternal: isExternal, target: self, action: #selector(performReferenceMenuAction(_:))
        )
        menu.popUp(positioning: nil, at: contentView.convert(location, from: nil), in: contentView)
    }

    /// コンテキストメニューの各項目の実行を、既存の遷移・Finder・クリップボード処理へ委譲する。
    @objc private func performReferenceMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? ReferenceMenuInvocation else { return }
        switch invocation.action {
        case let .open(disposition):
            // 外部 URL(http/https)はファイルビューア経路(switchFile/openFileElsewhere)に
            // ローカルパスが無く、渡すと「ファイルが見つかりません」になる。修飾キーに
            // かかわらずブラウザで開く(通常クリック・cmd+クリックと同じ扱いに揃える)。
            if invocation.isExternal {
                externalOpener(invocation.url)
            } else {
                openReference(invocation.url, disposition: disposition)
            }
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([invocation.url])
        case .copyName:
            writeToPasteboard(invocation.url.lastPathComponent)
        case .copyRelativePath:
            writeToPasteboard(PathRelativizer.relativePath(of: invocation.url, relativeTo: referenceBaseURL))
        }
    }

    /// NSPasteboard.general へ文字列を書き込む(FileListView の copyPath と同じ処理)。
    private func writeToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
