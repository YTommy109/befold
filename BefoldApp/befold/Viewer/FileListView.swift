import SwiftUI

/// サイドバーのファイル一覧と選択状態を保持する監視可能モデル。
/// リネームやディレクトリの変化に追従して一覧・選択を更新できるよう、
/// ウィンドウ側(ViewerWindowController)が参照型で保持して書き換える。
@MainActor
@Observable
final class FileListModel {
    var currentDirectory: URL
    var entries: [FileListEntry]
    var selection: FileListEntry.ID?
    var sortOrder: SortOrder

    init(currentDirectory: URL, entries: [FileListEntry], selection: FileListEntry.ID?) {
        self.currentDirectory = currentDirectory
        self.entries = entries
        self.selection = selection
        sortOrder = .foldersFirst
    }
}

struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void

    var body: some View {
        List(model.entries, selection: $model.selection) { entry in
            Label {
                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        }
        .onChange(of: model.selection) { _, newValue in
            if let url = newValue,
               model.entries.first(where: { $0.id == url })?.kind == .file
            {
                onSelect(url)
            }
        }
    }
}
