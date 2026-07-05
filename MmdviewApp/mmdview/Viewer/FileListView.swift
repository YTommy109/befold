import SwiftUI

/// サイドバーのファイル一覧と選択状態を保持する監視可能モデル。
/// リネームやディレクトリの変化に追従して一覧・選択を更新できるよう、
/// ウィンドウ側(ViewerWindowController)が参照型で保持して書き換える。
@MainActor
@Observable
final class FileListModel {
    var files: [URL]
    var selection: URL?

    init(files: [URL], selection: URL?) {
        self.files = files
        self.selection = selection
    }
}

struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void

    var body: some View {
        List(model.files, id: \.self, selection: $model.selection) { file in
            Label {
                Text(file.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        }
        .onChange(of: model.selection) { _, newValue in
            if let url = newValue {
                onSelect(url)
            }
        }
    }
}
