import AppKit
import BefoldKit
import SwiftUI

/// ブックマーク管理パネルの中身。フォルダーのツリーと、行の右クリックからの操作
/// (別名変更・削除・フォルダーの作成/改名/削除・フォルダーへ移動)。
///
/// 一覧は `BookmarkManagerModel` のスナップショットだけを描く。**存在確認(stat)はしない**
/// (`BookmarksMenuController` と同じ約束。応答しないマウントで待たされるため)。
/// 開けないブックマークの一括削除はメニューの「開けないブックマークを削除…」に任せる。
///
/// 文字入力(別名・フォルダー名)は `.alert` に `TextField` を置く形にする。インライン編集は
/// アプリ内に前例が無く、`List` 行の編集モードを自前で持つより小さい。用件の違いは
/// `BookmarkManagerPrompt` が持ち、文字入力の alert は 1 つ(名前の重複を伝える alert は別)。
@MainActor
struct BookmarkManagerView: View {
    let model: BookmarkManagerModel

    /// 選択中の行。Delete キーの対象と、「新規フォルダー」の置き場所(選択中のフォルダー)になる。
    @State private var selection: BookmarkRow?
    /// 文字入力中の用件。nil なら alert は出ていない。
    @State private var prompt: BookmarkManagerPrompt?
    @State private var draft = ""
    /// フォルダー名が同じ親の下で重複したとき(作成・改名・削除の繰り上げ)に出す。
    @State private var showsDuplicateFolderName = false

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            HStack {
                Button(String(localized: "bookmarks.manager.newFolder", bundle: .l10n)) {
                    start(.newFolder(parent: selectedFolderPath))
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(minWidth: 400, minHeight: 300)
        // 窓側の ⌘D や CLI で変わった分を、パネルが前面に来たときに拾う。
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refresh()
        }
        .alert(promptTitle, isPresented: isPrompting, presenting: prompt) { prompt in
            TextField(String(localized: prompt.placeholderKey, bundle: .l10n), text: $draft)
            Button(String(localized: prompt.applyKey, bundle: .l10n)) { apply(prompt) }
            Button(String(localized: "alert.cancel", bundle: .l10n), role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
        .alert(
            String(localized: "bookmarks.manager.duplicateFolder.message", bundle: .l10n),
            isPresented: $showsDuplicateFolderName
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        let root = model.children(of: [])
        if root.isEmpty {
            Text(String(localized: "bookmarks.manager.empty", bundle: .l10n))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                childrenView(root)
            }
            .onDeleteCommand { deleteSelected() }
        }
    }

    /// 1 段ぶんの行。フォルダーは `DisclosureGroup` で、中身はこの関数を再帰で呼んで作る。
    /// 再帰は `AnyView` で切る(opaque な戻り値型が自分自身を含めない)。
    @ViewBuilder
    private func childrenView(_ children: BookmarkChildren) -> some View {
        ForEach(children.folders, id: \.path) { folder in
            DisclosureGroup(isExpanded: expansion(of: folder)) {
                AnyView(childrenView(model.children(of: folder.path)))
            } label: {
                folderRow(folder)
            }
            .tag(BookmarkRow.folder(folder.path))
        }
        ForEach(children.entries, id: \.path) { entry in
            bookmarkRow(entry)
                .tag(BookmarkRow.bookmark(entry.path))
        }
    }

    private func folderRow(_ folder: BookmarkFolder) -> some View {
        Label(folder.name, systemImage: "folder")
            .contentShape(.rect)
            .contextMenu {
                Button(String(localized: "bookmarks.manager.renameFolder", bundle: .l10n)) {
                    start(.renameFolder(folder.path))
                }
                Button(String(localized: "bookmarks.manager.newFolder", bundle: .l10n)) {
                    start(.newFolder(parent: folder.path))
                }
                Button(String(localized: "bookmarks.manager.deleteFolder", bundle: .l10n)) {
                    deleteFolder(at: folder.path)
                }
            }
    }

    private func bookmarkRow(_ entry: BookmarkEntry) -> some View {
        HStack(spacing: 8) {
            // ファイル種別ごとのアイコン(`NSWorkspace.icon(forFile:)`)はディスク I/O を伴うため使わない。
            Image(systemName: "bookmark")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                Text(entry.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .contentShape(.rect)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.open(entry.url) })
        .contextMenu {
            Button(String(localized: "bookmarks.manager.renameAlias", bundle: .l10n)) {
                start(.alias(entry))
            }
            moveMenu(for: entry)
            // 文言は Bookmarks メニューのトグル(解除側)と揃える。
            Button(String(localized: "menu.bookmarks.remove", bundle: .l10n)) {
                remove(entry)
            }
        }
    }

    /// 「フォルダーへ移動」。トップレベルと全フォルダー(経路順)を並べ、いま居る場所は選べなくする。
    private func moveMenu(for entry: BookmarkEntry) -> some View {
        let current = model.library.resolvedFolder(of: entry)
        return Menu(String(localized: "bookmarks.manager.moveToFolder", bundle: .l10n)) {
            Button(String(localized: "bookmarks.manager.topLevel", bundle: .l10n)) {
                model.move(entry.url, to: [])
            }
            .disabled(current.isEmpty)
            ForEach(model.library.foldersSortedByPath, id: \.path) { folder in
                Button(folder.path.joined(separator: " / ")) {
                    model.move(entry.url, to: folder.path)
                }
                .disabled(folder.path == current)
            }
        }
    }

    // MARK: - 操作

    private func expansion(of folder: BookmarkFolder) -> Binding<Bool> {
        Binding(
            get: { folder.isExpanded },
            set: { model.setExpanded($0, for: folder.path) }
        )
    }

    /// 選択中の行が属するフォルダー(フォルダー行ならそれ自身、未選択ならルート)。
    private var selectedFolderPath: [String] {
        switch selection {
        case let .folder(path):
            return path
        case let .bookmark(path):
            guard let entry = model.library.entry(atPath: path) else { return [] }
            return model.library.resolvedFolder(of: entry)
        case nil:
            return []
        }
    }

    private func start(_ prompt: BookmarkManagerPrompt) {
        draft = prompt.initialText
        self.prompt = prompt
    }

    private var promptTitle: String {
        prompt.map { String(localized: $0.titleKey, bundle: .l10n) } ?? ""
    }

    private var isPrompting: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }

    private func apply(_ prompt: BookmarkManagerPrompt) {
        switch prompt {
        case let .alias(entry):
            model.setAlias(draft, for: entry.url)
        case let .newFolder(parent):
            // 空の名前は何もしない(重複ではないので alert も出さない)。規則はライブラリ側と同じもの。
            guard let name = BookmarkLibrary.folderName(draft) else { return }
            showsDuplicateFolderName = !model.createFolder(named: name, in: parent)
        case let .renameFolder(path):
            guard let name = BookmarkLibrary.folderName(draft) else { return }
            showsDuplicateFolderName = !model.renameFolder(at: path, to: name)
            if !showsDuplicateFolderName, selection == .folder(path) { selection = nil }
        }
    }

    private func deleteSelected() {
        switch selection {
        case let .bookmark(path):
            guard let entry = model.library.entry(atPath: path) else { return }
            remove(entry)
        case let .folder(path):
            deleteFolder(at: path)
        case nil:
            return
        }
    }

    private func remove(_ entry: BookmarkEntry) {
        model.remove(entry.url)
        if selection == .bookmark(entry.path) { selection = nil }
    }

    /// 配下は親へ繰り上がる。繰り上げ先で名前が衝突したら消さずに知らせる。
    private func deleteFolder(at path: [String]) {
        showsDuplicateFolderName = !model.deleteFolder(at: path)
        if !showsDuplicateFolderName, selection == .folder(path) { selection = nil }
    }
}
