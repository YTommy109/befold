import BefoldTestSupport
import Foundation
import Testing

/// 素の `Localizable.xcstrings` を読む経路(CI の `swift test` はこちら)が、複数形だけの
/// 訳を「訳漏れ」とせず `other` を代表として読むこと。手元の環境はコンパイル済みの
/// `.strings` 経路を通るため、この経路は手元の全体テストでは通らない。
struct LocalizableCatalogTests {
    @Test("variations.plural だけを持つエントリは other を訳として読む")
    func pluralOnlyEntryReadsOther() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalizableCatalogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        {"sourceLanguage":"en","version":"1.0","strings":{
          "plain":{"localizations":{"en":{"stringUnit":{"state":"translated","value":"x"}}}},
          "count %lld":{"localizations":{
            "en":{"variations":{"plural":{
              "one":{"stringUnit":{"state":"translated","value":"%lld item"}},
              "other":{"stringUnit":{"state":"translated","value":"%lld items"}}}}},
            "ja":{"variations":{"plural":{
              "other":{"stringUnit":{"state":"translated","value":"%lld 項目"}}}}}}}}}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("Localizable.xcstrings"))
        let bundle = try #require(Bundle(url: dir))

        let catalog = try LocalizableCatalog.load(bundle: bundle)

        #expect(catalog["plain"]?["en"] == "x")
        #expect(catalog["count %lld"]?["en"] == "%lld items")
        #expect(catalog["count %lld"]?["ja"] == "%lld 項目")
    }
}
