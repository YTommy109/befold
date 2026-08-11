import AppKit
import BefoldKit

// MARK: - References

/// 本文中のリンク・パス参照を「開く / 見つからないと伝える / 右クリックメニューを出す」層。
///
/// 解決そのもの(索引の先読み・相対パスの解決・外部 URL の判別)は
/// `ReferenceResolutionCoordinator` が持ち、ここはその結果をウィンドウの操作へ繋ぐ。
///
/// 右クリックメニューは `ReferenceMenuPresenter` が丸ごと担う(項目定義・表示・実行が
/// 1 つの流れなので、離すと `#selector` の対応が読めなくなる)。ここはその呼び出しだけ。
@MainActor
extension ViewerWindowController {
    /// 解決結果の届け先。生成は referenceCoordinator / referenceMenu の 1 箇所ずつだけ。
    /// 循環参照を避けるため、いずれの処理も self を弱参照で捕捉する。
    var referenceActions: ReferenceActions {
        ReferenceActions(
            open: { [weak self] url, disposition in self?.openReference(url, disposition: disposition) },
            presentNotFound: { [weak self] url in self?.presentReferenceNotFound(url: url) },
            presentContextMenu: { [weak self] url, isExternal in
                self?.presentReferenceContextMenu(for: url, isExternal: isExternal)
            }
        )
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

    /// リンク/パス参照の ctrl+クリック(右クリック)でコンテキストメニューを表示する。
    /// 項目定義・表示・実行は ReferenceMenuPresenter に閉じている(`@objc` アクションも向こう側)。
    func presentReferenceContextMenu(for url: URL, isExternal: Bool) {
        referenceMenu.present(for: url, isExternal: isExternal, in: window)
    }
}
