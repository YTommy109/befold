import Foundation
@testable import befold
import Testing

@Suite
struct GitHubReleaseTests {
    private let apiJSON = Data("""
    {
      "tag_name": "v1.2.0",
      "html_url": "https://github.com/YTommy109/befold/releases/tag/v1.2.0",
      "assets": [
        {
          "name": "befold-v1.2.0.dmg",
          "browser_download_url": "https://github.com/YTommy109/befold/releases/download/v1.2.0/befold-v1.2.0.dmg"
        }
      ]
    }
    """.utf8)

    @Test
    func decodeLatestReleaseResponse() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: apiJSON)
        #expect(release.tagName == "v1.2.0")
        #expect(release.htmlURL.absoluteString == "https://github.com/YTommy109/befold/releases/tag/v1.2.0")
        #expect(release.assets.count == 1)
        #expect(release.assets[0].name == "befold-v1.2.0.dmg")
    }

    @Test
    func downloadURLPrefersDmgAsset() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: apiJSON)
        #expect(release.downloadURL.absoluteString.hasSuffix("befold-v1.2.0.dmg"))
    }

    @Test
    func downloadURLSkipsNonDmgAssetsAndPicksDmg() throws {
        let json = Data("""
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/YTommy109/befold/releases/tag/v1.2.0",
          "assets": [
            {
              "name": "befold-v1.2.0.zip",
              "browser_download_url": "https://github.com/YTommy109/befold/releases/download/v1.2.0/befold-v1.2.0.zip"
            },
            {
              "name": "befold-v1.2.0.dmg",
              "browser_download_url": "https://github.com/YTommy109/befold/releases/download/v1.2.0/befold-v1.2.0.dmg"
            }
          ]
        }
        """.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(release.downloadURL.absoluteString.hasSuffix("befold-v1.2.0.dmg"))
    }

    @Test
    func downloadURLFallsBackToReleasePage() throws {
        let release = try GitHubRelease(
            tagName: "v1.2.0",
            htmlURL: #require(URL(string: "https://github.com/YTommy109/befold/releases/tag/v1.2.0")),
            assets: []
        )
        #expect(release.downloadURL == release.htmlURL)
    }
}
