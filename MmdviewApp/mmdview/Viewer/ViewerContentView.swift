import SwiftUI

struct ViewerContentView: View {
    var store: ViewerStore

    var body: some View {
        ViewerWebView(
            content: store.content,
            fileType: store.fileType,
            isDeleted: store.isDeleted
        )
    }
}
