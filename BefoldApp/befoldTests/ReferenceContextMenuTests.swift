import AppKit
@testable import befold
import BefoldKit
import Testing

/// makeMenu のテスト用ダミーターゲット。NSMenuItem の action は Selector を要求するため
/// 実在するオブジェクト+セレクタが要る(呼び出されることはない)。
@MainActor
private final class DummyMenuTarget: NSObject {
    @objc func noop(_: NSMenuItem) {}
}

@Suite
struct ReferenceContextMenuTests {
    @Test("ローカルファイルでは 6 項目すべてが有効になる")
    func localFileEnablesEveryItem() {
        let items = ReferenceContextMenu.items(isExternal: false)

        #expect(items.map(\.action) == [
            .open(.currentTab), .open(.newTab), .open(.newWindow),
            .revealInFinder, .copyName, .copyRelativePath,
        ])
        let allEnabled = items.allSatisfy(\.isEnabled)
        #expect(allEnabled)
    }

    @Test("外部 URL では Finder で開くと相対パスのコピーを無効にする")
    func externalURLDisablesFileOnlyItems() {
        let items = ReferenceContextMenu.items(isExternal: true)

        let disabled = items.filter { !$0.isEnabled }.map(\.action)
        #expect(disabled == [.revealInFinder, .copyRelativePath])
    }

    @Test("項目の文言はサイドバーのコンテキストメニューと同じキーを使う")
    func titlesReuseSidebarKeys() {
        let keys = ReferenceContextMenu.items(isExternal: false).map(\.titleKey)

        #expect(keys == [
            "sidebar.context.open",
            "sidebar.context.openInNewTab",
            "sidebar.context.openInNewWindow",
            "sidebar.context.revealInFinder",
            "sidebar.context.copy",
            "sidebar.context.copyPath",
        ])
    }

    // MARK: - makeMenu(NSMenu への反映)

    /// NSMenu は既定で autoenablesItems == true であり、その場合 target の
    /// validateMenuItem(_:) が isEnabled を再計算して上書きしてしまう。
    /// makeMenu がこれを明示的に無効化していることを固定する(データが正しくても
    /// NSMenu 側が isEnabled を捨てる回帰を防ぐ)。
    @Test("makeMenu は autoenablesItems を無効化し isEnabled をそのまま反映する")
    @MainActor
    func makeMenuDisablesAutoEnabling() {
        let target = DummyMenuTarget()
        let menu = ReferenceContextMenu.makeMenu(
            for: URL(filePath: "/tmp/a.md"), isExternal: true, target: target, action: #selector(DummyMenuTarget.noop)
        )

        #expect(menu.autoenablesItems == false)
        // 区切り線(NSMenuItem.separator())は isEnabled == false のまま挿入されるため、
        // items(isExternal:) の並びに区切り線の分の false を挟んだものと一致させる。
        #expect(menu.items.map(\.isEnabled) == [true, true, true, false, false, false, true, false])
    }

    @Test("makeMenu は区切り線を新規ウィンドウ/Finder の直後に 1 回ずつ入れる")
    @MainActor
    func makeMenuInsertsSeparatorsAfterConfiguredItems() {
        let target = DummyMenuTarget()
        let menu = ReferenceContextMenu.makeMenu(
            for: URL(filePath: "/tmp/a.md"), isExternal: false, target: target, action: #selector(DummyMenuTarget.noop)
        )

        #expect(menu.items.map(\.isSeparatorItem) == [false, false, false, true, false, true, false, false])
    }
}
