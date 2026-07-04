import Foundation
@testable import mmdview
import Testing

/// Localizable.xcstrings の訳の完全性を検証する。
/// swift test(SwiftPM)では String Catalog がコンパイルされず素の JSON のまま
/// バンドルされ、xcodebuild では .lproj/Localizable.strings にコンパイルされる。
/// どちらのビルドでも検証できるよう、両形式から訳を読み取る。
@Suite
struct LocalizationTests {
    private static let languages = ["en", "ja"]

    @Test("全キーに en / ja 両方の訳がある(訳漏れ検出)")
    func allKeysHaveBothLanguages() throws {
        let catalog = try loadCatalog()

        #expect(!catalog.isEmpty)
        for (key, translations) in catalog {
            for language in Self.languages {
                let value = translations[language]
                #expect(
                    value?.isEmpty == false,
                    "キー \(key) に \(language) の訳がありません"
                )
            }
        }
    }

    @Test("代表キーが期待する訳を持つ")
    func representativeKeysHaveExpectedValues() throws {
        let catalog = try loadCatalog()

        #expect(catalog["menu.file.open"]?["ja"] == "開く…")
        #expect(catalog["menu.file.open"]?["en"] == "Open…")
        #expect(catalog["menu.app.quit"]?["ja"] == "mmdview を終了")
        #expect(catalog["menu.app.quit"]?["en"] == "Quit mmdview")
        #expect(catalog["update.later"]?["ja"] == "後で")
        #expect(catalog["update.later"]?["en"] == "Later")
    }

    /// key -> 言語 -> 訳 の辞書を返す。
    private func loadCatalog() throws -> [String: [String: String]] {
        if let url = Bundle.l10n.url(forResource: "Localizable", withExtension: "xcstrings") {
            return try parseStringCatalog(url)
        }
        return try loadCompiledStrings()
    }

    private func parseStringCatalog(_ url: URL) throws -> [String: [String: String]] {
        struct CatalogFile: Decodable {
            struct Entry: Decodable {
                struct Localization: Decodable {
                    struct StringUnit: Decodable { let value: String }
                    let stringUnit: StringUnit
                }

                let localizations: [String: Localization]?
            }

            let strings: [String: Entry]
        }
        let file = try JSONDecoder().decode(CatalogFile.self, from: Data(contentsOf: url))
        return file.strings.mapValues { entry in
            (entry.localizations ?? [:]).mapValues(\.stringUnit.value)
        }
    }

    private func loadCompiledStrings() throws -> [String: [String: String]] {
        var catalog: [String: [String: String]] = [:]
        for language in Self.languages {
            let url = try #require(Bundle.l10n.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: language
            ))
            let entries = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for (key, value) in entries {
                catalog[key, default: [:]][language] = value
            }
        }
        return catalog
    }
}
