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
    var feedURLString: String {
        switch self {
        case .stable:
            "https://befold-site.tokutomi.workers.dev/appcast.xml"
        case .develop:
            "https://befold-site.tokutomi.workers.dev/appcast-develop.xml"
        }
    }
}
