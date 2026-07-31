import SwiftUI

/// Help > キーボードショートカット の中身。MainMenuBuilder に実装済みのショートカットを
/// メニューごとにグループ化して一覧表示する。
struct KeyboardShortcutsView: View {
    private struct Shortcut: Identifiable {
        let id = UUID()
        let key: String
        let title: LocalizedStringResource
    }

    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let shortcuts: [Shortcut]
    }

    private let groups: [Group] = [
        Group(title: "befold", shortcuts: [
            Shortcut(key: "⌘,", title: "menu.app.settings"),
            Shortcut(key: "⌘H", title: "menu.app.hide"),
            Shortcut(key: "⌥⌘H", title: "menu.app.hideOthers"),
            Shortcut(key: "⌘Q", title: "menu.app.quit"),
        ]),
        Group(title: "menu.file.title", shortcuts: [
            Shortcut(key: "⌘O", title: "menu.file.open"),
            Shortcut(key: "⌘P", title: "menu.file.quickOpen"),
            Shortcut(key: "⌘W", title: "menu.file.close"),
            Shortcut(key: "⇧⌘P", title: "menu.file.print"),
        ]),
        Group(title: "menu.edit.title", shortcuts: [
            Shortcut(key: "⌘Z", title: "menu.edit.undo"),
            Shortcut(key: "⇧⌘Z", title: "menu.edit.redo"),
            Shortcut(key: "⌘X", title: "menu.edit.cut"),
            Shortcut(key: "⌘C", title: "menu.edit.copy"),
            Shortcut(key: "⌘V", title: "menu.edit.paste"),
            Shortcut(key: "⌘A", title: "menu.edit.selectAll"),
            Shortcut(key: "⌘F", title: "menu.edit.find"),
            Shortcut(key: "⌘G", title: "menu.edit.findNext"),
            Shortcut(key: "⇧⌘G", title: "menu.edit.findPrevious"),
        ]),
        Group(title: "menu.view.title", shortcuts: [
            Shortcut(key: "⌘0", title: "menu.view.actualSize"),
            Shortcut(key: "⌘+", title: "menu.view.zoomIn"),
            Shortcut(key: "⌘-", title: "menu.view.zoomOut"),
            Shortcut(key: "⌘U", title: "menu.view.toggleSource"),
            Shortcut(key: "⌘L", title: "menu.view.showLineNumbers"),
            Shortcut(key: "⌘D", title: "menu.view.addBookmark"),
            Shortcut(key: "⌘S", title: "menu.view.toggleSidebar"),
            Shortcut(key: "⌘[", title: "menu.view.goBack"),
            Shortcut(key: "⌘]", title: "menu.view.goForward"),
            Shortcut(key: "⌃⌘H", title: "menu.view.showHiddenFiles"),
            Shortcut(key: "⌃⌘F", title: "menu.view.enterFullScreen"),
        ]),
        Group(title: "menu.window.title", shortcuts: [
            Shortcut(key: "⌘M", title: "menu.window.minimize"),
        ]),
        Group(title: "menu.help.title", shortcuts: [
            Shortcut(key: "⌘?", title: "menu.help.appHelp"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title == "befold" ? "befold" : String(
                            localized: String.LocalizationValue(group.title),
                            bundle: .l10n
                        ))
                        .font(.headline)
                        .textSelection(.enabled)
                        ForEach(group.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.title)
                                    .textSelection(.enabled)
                                Spacer()
                                Text(shortcut.key)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 320)
    }
}
