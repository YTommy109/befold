import Foundation
import Testing

/// `Localizable.xcstrings` の翻訳表を読み取る共有ヘルパー(TASK-618)。
///
/// `swift test`(SwiftPM)では String Catalog がコンパイルされず素の JSON のまま
/// バンドルされ、`xcodebuild` では `.lproj/Localizable.strings` にコンパイルされる。
/// どちらの環境でも読めるよう両形式に対応する。
///
/// **`String(localized:)` の解決結果と比較して「訳があるか」を確かめてはならない**
/// (実測: TASK-618)。`swift test` 環境では String Catalog が未コンパイルのため、
/// キーが実在していても `String(localized:)` は常にキー文字列をそのまま返す。
/// つまり `String(localized:)` の戻り値を使う限り、キーの有無を実行時には
/// 判別できない。このため訳の有無は常にこのカタログを直接読んで確かめる。
public enum LocalizableCatalog {
    private static let languages = ["en", "ja"]

    /// key -> 言語 -> 訳 の辞書を返す。
    public static func load(bundle: Bundle) throws -> [String: [String: String]] {
        if let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings") {
            return try parseStringCatalog(url)
        }
        return try loadCompiledStrings(bundle: bundle)
    }

    /// ネストを 2 段までに抑えるため、`Localization` / `StringUnit` は `CatalogFile` の
    /// 外に出してある(`CatalogFile.Entry` の 1 段のみが入れ子)。
    private struct CatalogStringUnit: Decodable { let value: String }

    private struct CatalogLocalization: Decodable { let stringUnit: CatalogStringUnit }

    private struct CatalogFile: Decodable {
        struct Entry: Decodable {
            let localizations: [String: CatalogLocalization]?
        }

        let strings: [String: Entry]
    }

    private static func parseStringCatalog(_ url: URL) throws -> [String: [String: String]] {
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

public extension String.LocalizationValue {
    /// テストからカタログを引くための、元のキー文字列。
    ///
    /// `String.LocalizationValue` はキー文字列を公開 API で取り出せない。
    /// `String(describing:)` は `LocalizationValue(arguments: [], key: "...")` という
    /// 別形式の説明文を返すだけで、キー文字列そのものではない(実測: TASK-618)。
    /// そこで `Mirror` でリフレクションし、`key` ラベルの子要素を取り出す。
    /// private な内部表現への依存のため、Swift のバージョンが上がったら
    /// (`BefoldCLIOptionValidationTests` と同じ手口の)この抽出が壊れていないか再確認すること。
    var rawKeyForTesting: String {
        guard let key = Mirror(reflecting: self).children
            .first(where: { $0.label == "key" })?.value as? String
        else {
            preconditionFailure(
                "String.LocalizationValue から key を取り出せなかった(内部表現が変わった可能性)"
            )
        }
        return key
    }
}
