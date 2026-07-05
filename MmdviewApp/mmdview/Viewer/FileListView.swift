import SwiftUI

struct FileListView: View {
    let files: [URL]
    @State private var selection: URL?
    let onSelect: (URL) -> Void

    init(files: [URL], initialSelection: URL, onSelect: @escaping (URL) -> Void) {
        self.files = files
        _selection = State(initialValue: initialSelection)
        self.onSelect = onSelect
    }

    var body: some View {
        List(files, id: \.self, selection: $selection) { file in
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
        .onChange(of: selection) { _, newValue in
            if let url = newValue {
                onSelect(url)
            }
        }
    }
}
