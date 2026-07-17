import BefoldKit
import SwiftUI

/// 巨大ファイルの読み込み中(デコード・行インデックス構築等)、まだ内容を表示できていない間に
/// ウィンドウ中央へ表示する不確定プログレスインジケータ。
struct LoadingIndicatorView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "viewer.loading", bundle: .l10n))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
