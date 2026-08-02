@testable import befold
import BefoldKit
import BefoldTestSupport
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
        let catalog = try Self.loadCatalog(bundle: bundle)

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

    /// 代表キー1件の期待値。`exact` が指定されていれば厳密一致、`nil` なら
    /// 「訳が空でないこと」だけを見る(BefoldKit 側は文言が変わりうるため)。
    private struct RepresentativeKey: Sendable, CustomTestStringConvertible {
        let bundle: Bundle
        let key: String
        let language: String
        let exact: String?
        var testDescription: String {
            "\(key)[\(language)]"
        }
    }

    private static let representativeKeys: [RepresentativeKey] = [
        RepresentativeKey(bundle: .l10n, key: "menu.file.open", language: "ja", exact: "開く…"),
        RepresentativeKey(bundle: .l10n, key: "menu.file.open", language: "en", exact: "Open…"),
        RepresentativeKey(bundle: .l10n, key: "menu.app.quit", language: "ja", exact: "befold を終了"),
        RepresentativeKey(bundle: .l10n, key: "menu.app.quit", language: "en", exact: "Quit befold"),
        RepresentativeKey(bundle: .l10n, key: "update.later", language: "ja", exact: "後で"),
        RepresentativeKey(bundle: .l10n, key: "update.later", language: "en", exact: "Later"),
        RepresentativeKey(bundle: .befoldKitResources, key: "viewer.find.placeholder", language: "en", exact: nil),
        RepresentativeKey(bundle: .befoldKitResources, key: "viewer.find.placeholder", language: "ja", exact: nil),
        RepresentativeKey(bundle: .befoldKitResources, key: "banner.showing", language: "en", exact: nil),
        RepresentativeKey(bundle: .befoldKitResources, key: "banner.showing", language: "ja", exact: nil),
        RepresentativeKey(bundle: .befoldKitResources, key: "viewer.unsupported.format", language: "en", exact: nil),
        RepresentativeKey(bundle: .befoldKitResources, key: "viewer.unsupported.format", language: "ja", exact: nil),
        RepresentativeKey(bundle: .befoldKitResources, key: "viewer.unsupported.tooLarge", language: "en", exact: nil),
        RepresentativeKey(bundle: .befoldKitResources, key: "viewer.unsupported.tooLarge", language: "ja", exact: nil),
    ]

    @Test("代表キーが期待する訳を持つ", arguments: representativeKeys)
    private func representativeKeyHasExpectedValue(_ representative: RepresentativeKey) throws {
        let catalog = try Self.cachedCatalog(bundle: representative.bundle)
        let value = catalog[representative.key]?[representative.language]

        if let exact = representative.exact {
            #expect(value == exact)
        } else {
            #expect(value?.isEmpty == false)
        }
    }

    /// パース済みカタログの static キャッシュ。代表キー検証をパラメタライズしたことで
    /// 同じ bundle のカタログをケースごとに読み直すことになるため、bundle 単位で使い回す。
    private static let catalogCache = LockedBox<[ObjectIdentifier: [String: [String: String]]]>([:])

    private static func cachedCatalog(bundle: Bundle) throws -> [String: [String: String]] {
        let key = ObjectIdentifier(bundle)
        if let cached = catalogCache.get()[key] { return cached }
        let catalog = try loadCatalog(bundle: bundle)
        catalogCache.update { $0[key] = catalog }
        return catalog
    }

    /// key -> 言語 -> 訳 の辞書を返す。
    private static func loadCatalog(bundle: Bundle) throws -> [String: [String: String]] {
        if let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings") {
            return try parseStringCatalog(url)
        }
        return try loadCompiledStrings(bundle: bundle)
    }

    private static func parseStringCatalog(_ url: URL) throws -> [String: [String: String]] {
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

    private static func loadCompiledStrings(bundle: Bundle) throws -> [String: [String: String]] {
        var catalog: [String: [String: String]] = [:]
        for language in languages {
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
