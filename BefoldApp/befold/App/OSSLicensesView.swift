import BefoldKit
import SwiftUI

/// Help > OSS 謝辞 の中身。BefoldKit に同梱の THIRD_PARTY_LICENSES.md をそのまま表示する。
struct OSSLicensesView: View {
    private let content: String

    init() {
        if let url = Bundle.befoldKitResources.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            content = text
        } else {
            content = String(localized: "ossLicenses.loadFailed", bundle: .l10n)
        }
    }

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
