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

    /// `.dmg` アセットの URL。なければリリースページにフォールバックする。
    var downloadURL: URL {
        assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }
}
