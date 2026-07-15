import BefoldKit
import SwiftUI

/// バイナリなど非対応内容のファイルを開いたときに、ウィンドウ中央に
/// アイコン・ファイル名・案内文を表示する。WKWebView は経由しない
/// (バイナリ内容を文字列として読み込む必要がないため)。
struct UnsupportedFileView: View {
    let fileURL: URL?
    let rejectReason: RejectReason

    var body: some View {
        VStack(spacing: 12) {
            if let fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        switch rejectReason {
        case .unsupportedFormat:
            String(localized: "viewer.unsupported.format", bundle: .l10n)
        case .fileTooLarge:
            String(localized: "viewer.unsupported.tooLarge", bundle: .l10n)
        }
    }
}
