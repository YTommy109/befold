import SwiftUI

struct ViewerBottomBar: View {
    let store: ViewerStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.showLineNumbers.toggle()
            } label: {
                Image(systemName: "list.number")
                    .foregroundStyle(store.showLineNumbers ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(store.showLineNumbers
                ? String(localized: "bottomBar.hideLineNumbers", bundle: .l10n)
                : String(localized: "bottomBar.showLineNumbers", bundle: .l10n))

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
