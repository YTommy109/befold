import AppKit
import BefoldKit
import SwiftUI

/// ブックマーク管理パネルの中身。一覧(表示名 + 親ディレクトリ)と、行の右クリックからの別名変更。
///
/// 一覧は `BookmarkManagerModel` のスナップショットだけを描く。**存在確認(stat)はしない**
/// (`BookmarksMenuController` と同じ約束。応答しないマウントで待たされるため)。
/// 開けないブックマークの一括削除はメニューの「開けないブックマークを削除…」に任せる。
///
/// 文字入力(別名)は `.alert` に `TextField` を置く形にする。インライン編集はアプリ内に前例が無く、
/// `List` 行の編集モードを自前で持つより小さい。
@MainActor
struct BookmarkManagerView: View {
    let model: BookmarkManagerModel

    /// 別名を編集中のエントリ。nil なら alert は出ていない。
    @State private var renaming: BookmarkEntry?
    @State private var aliasDraft = ""

    var body: some View {
        Group {
            if model.entries.isEmpty {
                Text(String(localized: "bookmarks.manager.empty", bundle: .l10n))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.entries, id: \.path) { entry in
                    row(for: entry)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        // 窓側の ⌘D や CLI で変わった分を、パネルが前面に来たときに拾う。
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refresh()
        }
        .alert(
            String(localized: "bookmarks.manager.renameAlias.title", bundle: .l10n),
            isPresented: isRenaming,
            presenting: renaming
        ) { entry in
            TextField(
                String(localized: "bookmarks.manager.renameAlias.placeholder", bundle: .l10n),
                text: $aliasDraft
            )
            Button(String(localized: "bookmarks.manager.renameAlias.apply", bundle: .l10n)) {
                model.setAlias(aliasDraft, for: entry.url)
            }
            Button(String(localized: "alert.cancel", bundle: .l10n), role: .cancel) {}
        } message: { entry in
            Text(entry.path)
        }
    }

    private func row(for entry: BookmarkEntry) -> some View {
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
                aliasDraft = entry.alias ?? ""
                renaming = entry
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
