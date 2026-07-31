import Foundation

/// アプリ外部リンクの単一情報源。
/// アプリ本体(About パネル)と QuickLook 拡張(バッジ)の双方から参照するため、
/// どちらからも import できる BefoldKit に置く。
public enum AppLinks {
    /// befold の公開サイト（配布サイト Worker）。
    /// `?ref=about` は流入元の内訳を配布サイト側で集計するための印。
    /// 既存ユーザーが About から見に来た分を、新規流入と切り分けて数えられる。
    public static let homepage = URL(string: "https://befold.tommy109.workers.dev/?ref=about")!

    /// Help > befold ヘルプ の遷移先。
    /// GitHub の README ではなく配布サイトへ送る。GitHub のページには Releases への
    /// 導線が常に出ており、そこから DMG を直接取得されると配布サイトの統計に載らないため。
    public static let help = URL(string: "https://befold.tommy109.workers.dev/?ref=help")!

    /// 作者(tommy109)の GitHub プロフィール。About パネルのクレジット表記から遷移する。
    public static let author = URL(string: "https://github.com/YTommy109")!
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
        guard let version = VersionFormatting.versionString(infoDictionary: infoDictionary) else {
            return "befold QL"
        }
        return "befold QL, version " + version
    }
}
