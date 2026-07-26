import Foundation

/// アプリ外部リンクの単一情報源。
/// アプリ本体(About パネル)と QuickLook 拡張(バッジ)の双方から参照するため、
/// どちらからも import できる BefoldKit に置く。
public enum AppLinks {
    /// befold の公開サイト。
    public static let homepage = URL(string: "https://ytommy109.github.io/befold/")!
}

/// QuickLook 拡張のプレビュー右下に重ねるバッジの表示文字列。
/// appex 側は表示だけを担い、文字列の組み立てはここに置いてテスト可能にする。
///
/// リンクにはしない。QuickLook のプレビュー拡張が動く sandbox profile
/// (quicklook-preview)は通常のアプリサンドボックスより厳しく、クリック自体は
/// 届くものの NSExtensionContext.open も NSWorkspace.open も false を返して
/// URL を開けないため(2026-07-26 / macOS 26.5.2 で実機確認)。
/// 押しても何も起きないリンク表示になるより、通常テキストの方がよい。
public enum QuickLookBadge {
    /// 例: `befold QL, version 1.7.3 (748)`
    /// appex では Bundle.main が appex 自身のバンドルを指す。バージョンは
    /// project.yml の settings.base で本体と同じ値が焼き込まれる。
    /// バージョンが取れない場合も、どの拡張が担当したかの識別だけは残す。
    public static func text(infoDictionary: [String: Any]?) -> String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String
        let build = infoDictionary?["CFBundleVersion"] as? String
        return switch (short, build) {
        case let (short?, build?): "befold QL, version \(short) (\(build))"
        case let (short?, nil): "befold QL, version \(short)"
        default: "befold QL"
        }
    }
}
