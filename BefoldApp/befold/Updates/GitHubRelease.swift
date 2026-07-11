import Foundation

/// GitHub Releases API(`releases/latest`)のレスポンス。
struct GitHubRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    /// `.dmg` アセットが添付されているか。
    var hasDMG: Bool {
        dmgAsset != nil
    }

    /// `.dmg` アセットの URL。なければリリースページにフォールバックする。
    /// スキームが https かつ許可ホストであることを検証する。
    var downloadURL: URL {
        guard let asset = dmgAsset,
              Self.isAllowedDownloadURL(asset.browserDownloadURL)
        else {
            return htmlURL
        }
        return asset.browserDownloadURL
    }

    private static let allowedHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
    ]

    private static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https",
              let host = url.host,
              allowedHosts.contains(host)
        else {
            return false
        }
        return true
    }

    private var dmgAsset: Asset? {
        assets.first { $0.name.hasSuffix(".dmg") }
    }
}
