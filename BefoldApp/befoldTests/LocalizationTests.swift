@testable import befold
import BefoldKit
import Foundation
import Testing

/// Localizable.xcstrings の訳の完全性を検証する。
/// swift test(SwiftPM)では String Catalog がコンパイルされず素の JSON のまま
/// バンドルされ、xcodebuild では .lproj/Localizable.strings にコンパイルされる。
/// どちらのビルドでも検証できるよう、両形式から訳を読み取る。
///
/// アプリ本体(Bundle.l10n)と BefoldKit(Bundle.befoldKitResources)の
/// 2 つのカタログに分かれているため、両方を検証する。
@Suite
struct LocalizationTests {
    private static let languages = ["en", "ja"]

    @Test("全キーに en / ja 両方の訳がある(訳漏れ検出)", arguments: [Bundle.l10n, Bundle.befoldKitResources])
    func allKeysHaveBothLanguages(bundle: Bundle) throws {
        let catalog = try loadCatalog(bundle: bundle)

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
        let catalog = try loadCatalog(bundle: .l10n)

        #expect(catalog["menu.file.open"]?["ja"] == "開く…")
        #expect(catalog["menu.file.open"]?["en"] == "Open…")
        #expect(catalog["menu.app.quit"]?["ja"] == "befold を終了")
        #expect(catalog["menu.app.quit"]?["en"] == "Quit befold")
        #expect(catalog["update.later"]?["ja"] == "後で")
        #expect(catalog["update.later"]?["en"] == "Later")
    }

    @Test("BefoldKit の代表キーが期待する訳を持つ")
    func befoldKitRepresentativeKeysHaveExpectedValues() throws {
        let catalog = try loadCatalog(bundle: .befoldKitResources)

        #expect(catalog["viewer.find.placeholder"]?["en"]?.isEmpty == false)
        #expect(catalog["viewer.find.placeholder"]?["ja"]?.isEmpty == false)
        #expect(catalog["banner.showing"]?["en"]?.isEmpty == false)
        #expect(catalog["banner.showing"]?["ja"]?.isEmpty == false)
        #expect(catalog["viewer.unsupported.format"]?["en"]?.isEmpty == false)
        #expect(catalog["viewer.unsupported.format"]?["ja"]?.isEmpty == false)
        #expect(catalog["viewer.unsupported.tooLarge"]?["en"]?.isEmpty == false)
        #expect(catalog["viewer.unsupported.tooLarge"]?["ja"]?.isEmpty == false)
    }

    /// key -> 言語 -> 訳 の辞書を返す。
    private func loadCatalog(bundle: Bundle) throws -> [String: [String: String]] {
        if let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings") {
            return try parseStringCatalog(url)
        }
        return try loadCompiledStrings(bundle: bundle)
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

    private func loadCompiledStrings(bundle: Bundle) throws -> [String: [String: String]] {
        var catalog: [String: [String: String]] = [:]
        for language in Self.languages {
            let url = try #require(bundle.url(
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
