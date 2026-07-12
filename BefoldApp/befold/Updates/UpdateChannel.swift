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
    var feedURLString: String {
        switch self {
        case .stable:
            "https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml"
        case .develop:
            "https://github.com/YTommy109/befold/releases/download/appcast/appcast-develop.xml"
        }
    }
}
