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

    /// ファイル URL の一覧を「ファイル名(左)＋親ディレクトリのパス(右)」の 2 列表示で追加する。
    /// 同名ファイルが別フォルダーにあるとき、メニュー上で区別できるようにするためのもの。
    /// 列の位置は与えられた URL 群の実測幅から決まるので、1 メニュー分をまとめて渡すこと。
    @MainActor
    @discardableResult
    func addFileItems(
        urls: [URL],
        action: Selector,
        target: AnyObject
    ) -> [NSMenuItem] {
        let titles = FileMenuTitleLayout(urls: urls)
        return urls.enumerated().map { index, url in
            let item = addFileItem(
                title: url.lastPathComponent, filePath: url.path,
                action: action, target: target, representedObject: url
            )
            item.attributedTitle = titles.attributedTitle(at: index)
            return item
        }
    }
}

/// 「ファイル名 + 右寄せのパス」メニュータイトルを組み立てる。
/// パスは右揃えのタブストップで揃えるため、列位置は一覧全体の実測幅から決める。
@MainActor
struct FileMenuTitleLayout {
    /// ファイル名とパスの間に最低限空ける幅。
    private static let columnGap: CGFloat = 24
    /// パス列に許す最大幅。これを超えるパスは先頭を省略記号に畳む。
    private static let maxPathWidth: CGFloat = 320

    private let nameFont = NSFont.menuFont(ofSize: 0)
    private let pathFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
    private let names: [String]
    private let paths: [String]
    private let tabLocation: CGFloat

    init(urls: [URL]) {
        let nameFont = NSFont.menuFont(ofSize: 0)
        let pathFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        names = urls.map(\.lastPathComponent)
        paths = urls.map { Self.displayPath(for: $0, font: pathFont) }
        let widest = zip(names, paths).map { name, path in
            Self.width(of: name, font: nameFont) + Self.width(of: path, font: pathFont)
        }.max() ?? 0
        tabLocation = widest + Self.columnGap
    }

    /// `index` 番目の項目の表示タイトル。パスは右端(タブストップ位置)で揃う。
    func attributedTitle(at index: Int) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabLocation)]
        let title = NSMutableAttributedString(
            string: names[index] + "\t",
            attributes: [.font: nameFont, .paragraphStyle: paragraph]
        )
        title.append(NSAttributedString(
            string: paths[index],
            attributes: [
                .font: pathFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        ))
        return title
    }

    /// 親ディレクトリのパス。ホーム配下は `~` に畳み、長すぎるものは先頭を `…` にする。
    private static func displayPath(for url: URL, font: NSFont) -> String {
        let full = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        guard width(of: full, font: font) > maxPathWidth else { return full }
        var components = full.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        while components.count > 1 {
            components.removeFirst()
            let candidate = "…/" + components.joined(separator: "/")
            if width(of: candidate, font: font) <= maxPathWidth { return candidate }
        }
        return "…/" + (components.last ?? "")
    }

    private static func width(of string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }
}
