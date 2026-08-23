import Foundation

/// アプリ外部リンクの単一情報源。
/// アプリ本体(About パネル)と QuickLook 拡張(バッジ)の双方から参照するため、
/// どちらからも import できる BefoldKit に置く。
public enum AppLinks {
    /// 配布サイトのオリジン。**アプリ側のホスト名リテラルはここだけに置く。**
    ///
    /// 散らすと、次にホストが変わったときに片側だけ直る（ADR 0007 の決定 6 が
    /// 配布サイト側に置いた規定を、アプリ側にも同じ理由で適用する）。Sparkle の
    /// フィード URL（`UpdateChannel.feedURLString`）もここから組む。
    ///
    /// `*.workers.dev` から独自ドメインへ移した理由は可搬性。独自ドメインは DNS で
    /// 向き先を差し替えられるが、`*.workers.dev` は Cloudflare アカウントに固定された
    /// ホスト名で、将来 Cloudflare 以外へ移す選択肢を塞ぐ（ADR 0007 の決定 3）。
    ///
    /// **旧ホスト（befold.tommy109.workers.dev）が止まる前提の実装をしてはならない。**
    /// 切り替えが効くのはこの変更を含むバージョンを入れたユーザーだけで、出荷済み
    /// アプリは旧ホストを見続ける。旧ホストは恒久的に維持する（同決定 1）。
    public static let siteOrigin = "https://befold.degino.com"

    /// befold の公開サイト（配布サイト Worker）。
    /// `?ref=about` は流入元の内訳を配布サイト側で集計するための印。
    /// 既存ユーザーが About から見に来た分を、新規流入と切り分けて数えられる。
    /// `ref` の値は変えない（変えると過去データと接続できなくなる）。
    public static let homepage = URL(string: siteOrigin + "/?ref=about")!

    /// Help > befold ヘルプ の遷移先。
    /// GitHub の README ではなく配布サイトへ送る。GitHub のページには Releases への
    /// 導線が常に出ており、そこから DMG を直接取得されると配布サイトの統計に載らないため。
    public static let help = URL(string: siteOrigin + "/?ref=help")!

    /// Help > GitHub Issues の遷移先。不具合報告・要望の受け口。
    ///
    /// `homepage` / `help` と違い `?ref=` を付けない。ref は配布サイト Worker が
    /// 自前で集計するための印であり、遷移先が GitHub の場合はこちらから内訳を
    /// 読めない。読めない印を付けると「付いているから数えられている」と誤解される。
    public static let issues = URL(string: "https://github.com/YTommy109/befold/issues")!

    /// 開発元(Degino Inc.)のコーポレートサイト。About パネルのクレジット表記から遷移する。
    ///
    /// `siteOrigin`(befold の配布サイト)とは別のホストなので、そちらから組まない。
    /// ホスト名リテラルをアプリ側へ散らさない規約に従い、ここに置く。
    public static let company = URL(string: "https://www.degino.com")!
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
