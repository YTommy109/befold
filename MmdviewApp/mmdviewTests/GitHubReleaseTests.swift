import Foundation
import Testing
@testable import mmdview

@Suite
struct GitHubReleaseTests {
    private let apiJSON = Data("""
    {
      "tag_name": "v1.2.0",
      "html_url": "https://github.com/YTommy109/mmdview/releases/tag/v1.2.0",
      "assets": [
        {
          "name": "mmdview-v1.2.0.dmg",
          "browser_download_url": "https://github.com/YTommy109/mmdview/releases/download/v1.2.0/mmdview-v1.2.0.dmg"
        }
      ]
    }
    """.utf8)

    @Test
    func decodeLatestReleaseResponse() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: apiJSON)
        #expect(release.tagName == "v1.2.0")
        #expect(release.htmlURL.absoluteString == "https://github.com/YTommy109/mmdview/releases/tag/v1.2.0")
        #expect(release.assets.count == 1)
        #expect(release.assets[0].name == "mmdview-v1.2.0.dmg")
    }

    @Test
    func downloadURLPrefersDmgAsset() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: apiJSON)
        #expect(release.downloadURL.absoluteString.hasSuffix("mmdview-v1.2.0.dmg"))
    }

    @Test
    func downloadURLSkipsNonDmgAssetsAndPicksDmg() throws {
        let json = Data("""
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/YTommy109/mmdview/releases/tag/v1.2.0",
          "assets": [
            {
              "name": "mmdview-v1.2.0.zip",
              "browser_download_url": "https://github.com/YTommy109/mmdview/releases/download/v1.2.0/mmdview-v1.2.0.zip"
            },
            {
              "name": "mmdview-v1.2.0.dmg",
              "browser_download_url": "https://github.com/YTommy109/mmdview/releases/download/v1.2.0/mmdview-v1.2.0.dmg"
            }
          ]
        }
        """.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(release.downloadURL.absoluteString.hasSuffix("mmdview-v1.2.0.dmg"))
    }

    @Test
    func downloadURLFallsBackToReleasePage() throws {
        let release = GitHubRelease(
            tagName: "v1.2.0",
            htmlURL: try #require(URL(string: "https://github.com/YTommy109/mmdview/releases/tag/v1.2.0")),
            assets: [])
        #expect(release.downloadURL == release.htmlURL)
    }
}
