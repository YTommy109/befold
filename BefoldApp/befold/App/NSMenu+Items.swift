import AppKit

/// メニュー項目生成のボイラープレート(target / representedObject / 16×16 アイコン)を
/// 1 箇所に集約する。Recent Documents・Recent Repositories・Bookmarks・戻る/進む履歴の
/// 各メニューが同型のコードを持っていたため、生成規則をここへ寄せる。
extension NSMenuItem {
    /// メニュー項目のアイコンサイズ。AppKit のメニューは 16pt を前提にしている。
    static let iconSize = NSSize(width: 16, height: 16)

    /// クリックで `target` のアクションを呼ぶ項目を作る。キー等価は付けない
    /// (この形で作るのは動的に再生成されるリスト項目のため)。
    static func action(
        title: String,
        action: Selector,
        target: AnyObject,
        representedObject: Any? = nil,
        image: NSImage? = nil,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = representedObject
        item.image = image
        item.tag = tag
        return item
    }

    /// ファイル/フォルダーのアイコンをメニュー用サイズで返す。
    /// パスに対する `NSWorkspace.icon(forFile:)` はディスク I/O を伴うため、
    /// 応答しないマウント上のパスに使わないこと(呼び出し側の判断)。
    static func icon(forFile path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path).sizedForMenuItem()
    }
}

extension NSImage {
    /// メニュー項目用に 16×16 へ揃えた自分自身を返す。
    /// `NSWorkspace` のアイコン取得は毎回新しいインスタンスを返すため、破壊的に縮めてよい。
    @discardableResult
    func sizedForMenuItem() -> NSImage {
        size = NSMenuItem.iconSize
        return self
    }
}

extension NSMenu {
    /// `NSMenuItem.action(...)` で作った項目を末尾へ追加する。
    @discardableResult
    func addActionItem(
        title: String,
        action: Selector,
        target: AnyObject,
        representedObject: Any? = nil,
        image: NSImage? = nil,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem.action(
            title: title, action: action, target: target,
            representedObject: representedObject, image: image, tag: tag
        )
        addItem(item)
        return item
    }

    /// ローカライズ済みタイトルの項目を末尾へ追加する(メインメニューの静的な項目用)。
    /// `modifiers` は既定(キー等価に応じた cmd)から変えるときだけ渡す。
    @discardableResult
    func addLocalizedItem(
        _ key: String.LocalizationValue,
        action: Selector?,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags? = nil
    ) -> NSMenuItem {
        let item = addItem(
            withTitle: String(localized: key, bundle: .l10n),
            action: action,
            keyEquivalent: keyEquivalent
        )
        if let modifiers { item.keyEquivalentModifierMask = modifiers }
        return item
    }

    /// ローカライズ済みタイトルのサブメニュー項目を末尾へ追加し、その NSMenu を返す。
    /// `delegate` を渡すと、表示直前に項目を組み立てる動的サブメニューになる。
    @discardableResult
    func addLocalizedSubmenu(
        _ key: String.LocalizationValue,
        delegate: NSMenuDelegate? = nil
    ) -> NSMenu {
        let title = String(localized: key, bundle: .l10n)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.delegate = delegate
        item.submenu = submenu
        addItem(item)
        return submenu
    }

    /// ファイルアイコン付きの項目を末尾へ追加する。
    @discardableResult
    func addFileItem(
        title: String,
        filePath: String,
        action: Selector,
        target: AnyObject,
        representedObject: Any? = nil,
        tag: Int = 0
    ) -> NSMenuItem {
        addActionItem(
            title: title, action: action, target: target,
            representedObject: representedObject,
            image: NSMenuItem.icon(forFile: filePath), tag: tag
        )
    }
}
