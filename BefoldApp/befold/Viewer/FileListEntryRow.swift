import AppKit
import SwiftUI

/// サイドバー(FileListView)とプレビュー内フォルダー一覧(FolderListingView)が
/// 共有する行表示。ここを一箇所にすることで両者の見た目の基準を一致させる。
struct FileListEntryRow: View {
    let entry: FileListEntry

    var body: some View {
        switch entry.kind {
        case .parentNavigation:
            HStack {
                Label {
                    Text("..")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "arrow.up.doc")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .folder:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        case .file:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(entry.hasUnknownExtension ? .secondary : .primary)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
            }
        }
    }
}
