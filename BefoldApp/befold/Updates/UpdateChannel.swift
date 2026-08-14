import BefoldKit
import Foundation

/// アップデートチェックの対象チャンネル(安定版 / 開発版)。
enum UpdateChannel: String, Sendable {
    case stable
    case develop

    static func read(from defaults: UserDefaults = .standard) -> UpdateChannel {
        defaults.string(forKey: "UpdateChannel")
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }

    /// Sparkle が参照する appcast フィード URL。
    ///
    /// 配布サイト(Cloudflare Worker)が GitHub の appcast をプロキシしつつ
    /// アップデートチェックを計測する。appcast の実体と DMG は従来どおり
    /// GitHub Releases にあり、旧 URL を見る既存ユーザーも壊れない。
    ///
    /// ホストは `AppLinks.siteOrigin` から組む。リテラルを持つと、次にホストが
    /// 変わったときに About のリンクだけ直って更新経路が取り残される。
    /// Sparkle への受け渡しは Info.plist の `SUFeedURL` ではなく
    /// `AppUpdaterController.feedURLString(for:)` 経由なので、変更点はここだけ。
    var feedURLString: String {
        switch self {
        case .stable:
            AppLinks.siteOrigin + "/appcast.xml"
        case .develop:
            AppLinks.siteOrigin + "/appcast-develop.xml"
        }
    }
}
