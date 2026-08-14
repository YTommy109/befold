import BefoldKit
import SwiftUI

/// 相対パスのコピーと Quick Open が基準にしているフォルダを、サイドバーヘッダー最上部で
/// 常時示す 1 行。アイコンで「git ルート基準か」を、ラベルで「どのフォルダか」を表す。
/// 情報表示のみでクリック操作は持たない。
///
/// 種別は `switch` で全件を書く。`BaseDirectoryDescriptor.Kind` に状態が増えたとき、
/// 二値判定(`== .gitRoot`)のままだと**増えた状態が黙って「git ではない側」へ倒れる**。
/// 扱えないリポジトリを「Plain folder」と表示していたのがまさにその形だった(TASK-438.1)。
struct BaseDirectoryIndicator: View {
    let base: BaseDirectoryDescriptor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(base.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(tooltip)
    }

    /// テストから読むため internal。表示の出し分けは 3 種別すべてを固定する
    /// (`BaseDirectoryIndicatorTests`)。
    ///
    /// 扱えないリポジトリでも git のアイコンを出す。基準ディレクトリは workspaceRoot へ
    /// 落ちているが、そこが git リポジトリであること自体は事実だから。
    var iconName: String {
        switch base.kind {
        case .gitRoot, .unusableRepository: "arrow.triangle.branch"
        case .plainFolder: "folder"
        }
    }

    /// 「何の基準か」「git かどうか」「どこか(フルパス)」の 3 行。
    /// 書式引数を使わず Swift 側で連結するのは、翻訳側に順序制約を持ち込まないため。
    ///
    /// 扱えないリポジトリでも**失敗の理由(partial clone / reftable / 未知の拡張)は出さない**。
    /// `GitLibrary.OpenFailure` が意図的に `.unusable` の 1 値へ畳んでおり、
    /// 理由別の文言は型が持っていない情報を騙ることになる(TASK-438)。
    var tooltip: String {
        let kindLabel = String(localized: kindLabelKey, bundle: .l10n)
        let caption = String(localized: "sidebar.baseDirectory.caption", bundle: .l10n)
        return "\(caption)\n\(kindLabel)\n\(base.url.standardizedFileURL.path)"
    }

    private var kindLabelKey: String.LocalizationValue {
        switch base.kind {
        case .gitRoot: "sidebar.baseDirectory.gitRepository"
        case .plainFolder: "sidebar.baseDirectory.plainFolder"
        case .unusableRepository: "sidebar.baseDirectory.unusableRepository"
        }
    }
}
