import AppKit
import BefoldKit
import Foundation

/// ビューア本文のリンク/パス参照に対するコンテキストメニューの項目定義。
/// 並びと文言をサイドバーのコンテキストメニューへ揃えるため、項目の組み立てをここに集約する。
enum ReferenceContextMenu {
    enum Action: Equatable {
        case open(OpenDisposition)
        case revealInFinder
        case copyName
        case copyRelativePath
    }

    struct Item: Equatable {
        let titleKey: String
        let action: Action
        let isEnabled: Bool
        /// この項目の直後に区切り線を置くか。並び順と区切り位置の単一情報源をここに保つ
        /// (NSMenu 組み立て側でアクション値から区切り位置を推測しない)。
        let isSeparatorAfter: Bool
    }

    /// - Parameter isExternal: 対象が http/https の外部 URL か。
    ///   外部 URL にはローカルパスが無いため、Finder と相対パスのコピーを無効にする。
    static func items(isExternal: Bool) -> [Item] {
        [
            Item(
                titleKey: "sidebar.context.open",
                action: .open(.currentTab),
                isEnabled: true,
                isSeparatorAfter: false
            ),
            Item(
                titleKey: "sidebar.context.openInNewTab",
                action: .open(.newTab),
                isEnabled: true,
                isSeparatorAfter: false
            ),
            Item(
                titleKey: "sidebar.context.openInNewWindow", action: .open(.newWindow), isEnabled: true,
                isSeparatorAfter: true
            ),
            Item(
                titleKey: "sidebar.context.revealInFinder", action: .revealInFinder, isEnabled: !isExternal,
                isSeparatorAfter: true
            ),
            Item(titleKey: "sidebar.context.copy", action: .copyName, isEnabled: true, isSeparatorAfter: false),
            Item(
                titleKey: "sidebar.context.copyPath", action: .copyRelativePath, isEnabled: !isExternal,
                isSeparatorAfter: false
            ),
        ]
    }

    /// `items(isExternal:)` から NSMenu を組み立てる。popUp するかどうかは呼び出し側(テストと
    /// ViewerWindowController)で分けられるよう、ここでは組み立てまでに留める。
    ///
    /// `autoenablesItems = false` を明示しないと、NSMenu は表示時に target の
    /// `validateMenuItem(_:)` を使って各項目の有効/無効を再計算してしまい、ここで設定した
    /// `isEnabled` が実行時に無視される(既定は true)。ViewerWindowController.validateMenuItem
    /// はこのメニューのアクションを認識せずフォールスルーで有効判定するため、
    /// これを外すと外部 URL でも Finder・相対パスコピーが有効になってしまう。
    @MainActor
    static func makeMenu(
        for url: URL, isExternal: Bool, target: AnyObject, action: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items(isExternal: isExternal) {
            let menuItem = NSMenuItem(
                title: String(localized: String.LocalizationValue(item.titleKey), bundle: .l10n),
                action: action, keyEquivalent: ""
            )
            menuItem.target = target
            menuItem.isEnabled = item.isEnabled
            menuItem.representedObject = ReferenceMenuInvocation(url: url, action: item.action, isExternal: isExternal)
            menu.addItem(menuItem)
            if item.isSeparatorAfter {
                menu.addItem(.separator())
            }
        }
        return menu
    }
}

/// メニュー項目 1 つが実行時に必要とする情報。NSMenuItem.representedObject へ載せる。
/// NSMenuItem 経由でしか使わない前提を型で明示するため MainActor に閉じる。
@MainActor
final class ReferenceMenuInvocation: NSObject {
    let url: URL
    let action: ReferenceContextMenu.Action
    /// 対象が http/https の外部 URL か。`.open(_)` の実行時に、外部 URL を
    /// ファイルビューア経路(switchFile/openFileElsewhere)へ渡さずブラウザへ送るために使う。
    let isExternal: Bool

    init(url: URL, action: ReferenceContextMenu.Action, isExternal: Bool) {
        self.url = url
        self.action = action
        self.isExternal = isExternal
    }
}
