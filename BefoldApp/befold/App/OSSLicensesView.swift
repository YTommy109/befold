import BefoldKit
import SwiftUI

/// Help > OSS 謝辞 の中身。BefoldKit に同梱の THIRD_PARTY_LICENSES.md を、
/// ビューア本体と同じレンダリング経路で表示する（Markdown で書かれた文書のため）。
struct OSSLicensesView: View {
    private let documentURL: URL?

    init() {
        documentURL = Bundle.befoldKitResources.url(
            forResource: "THIRD_PARTY_LICENSES", withExtension: "md"
        )
    }

    var body: some View {
        Group {
            if let documentURL {
                RenderedMarkdownView(
                    url: documentURL,
                    failureMessage: String(localized: "ossLicenses.loadFailed", bundle: .l10n)
                )
            } else {
                // リソースが見つからない場合。描画器まで行かずにここで縮退させる。
                Text("ossLicenses.loadFailed", bundle: .l10n)
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
