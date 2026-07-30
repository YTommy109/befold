import BefoldKit
import SwiftUI

/// 相対パスのコピーと Quick Open が基準にしているフォルダを、サイドバーヘッダー最上部で
/// 常時示す 1 行。アイコンで「git ルート基準か」を、ラベルで「どのフォルダか」を表す。
/// 情報表示のみでクリック操作は持たない。
struct BaseDirectoryIndicator: View {
    let base: BaseDirectoryDescriptor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: base.kind == .gitRoot ? "arrow.triangle.branch" : "folder")
            Text(base.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(tooltip)
    }

    /// 「何の基準か」「git かどうか」「どこか(フルパス)」の 3 行。
    /// 書式引数を使わず Swift 側で連結するのは、翻訳側に順序制約を持ち込まないため。
    private var tooltip: String {
        let kindLabel = base.kind == .gitRoot
            ? String(localized: "sidebar.baseDirectory.gitRepository", bundle: .l10n)
            : String(localized: "sidebar.baseDirectory.plainFolder", bundle: .l10n)
        let caption = String(localized: "sidebar.baseDirectory.caption", bundle: .l10n)
        return "\(caption)\n\(kindLabel)\n\(base.url.standardizedFileURL.path)"
    }
}
