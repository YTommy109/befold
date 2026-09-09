@testable import befold
import BefoldKit
import Foundation
import Testing

/// Swift↔JS ブリッジ契約テスト群が共有するヘルパー。
///
/// 同梱 JS/HTML のソースを読んで走査する処理は複数のスイート
/// (`ViewerBridgeContractTests` / `ViewerBridgeCsvNumberFormatTests` /
/// `ViewerFunctionJumpLanguageContractTests` / `ViewerJumpLevelContractTests`)が使う。
/// `@Suite` 型の static を他スイートから借りる形をやめ、共有面をここへ集約した
/// (`ViewerStoreTestSupport` などと同じ置き方)。
enum ViewerBridgeContractSupport {
    /// JS 側の 1 つの postMessage 送信サイト。
    struct PostSite {
        let messageName: String
        let payloadKeys: Set<String>
    }

    /// `global = { ... };` 形式のスクリプトから、注入される JSON オブジェクトのキー集合を取り出す。
    static func bridgeGlobalKeys(from script: String, global: String) throws -> [String] {
        let jsonPart = script
            .replacingOccurrences(of: "\(global) = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try #require(jsonPart.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Array(decoded.keys)
    }

    /// viewer-bundle.js から、オブジェクトリテラルをペイロードに渡す postMessage 送信サイトを
    /// すべて抽出する。zoomChanged のように裸の値を渡すサイトは対象外。
    static func objectPayloadSites() throws -> [PostSite] {
        let source = try viewerBundleSource()
        let messageNames = try messageNamesByJSConstant(in: source)

        // 例: _mmdPostMessage(_MSG_REFERENCE_ACTIVATED, { href, metaKey: e.metaKey, shiftKey: e.shiftKey });
        // ペイロードはネストしないオブジェクトリテラルのみを対象にする。
        let pattern = #"_mmdPostMessage\(\s*(_MSG_[A-Z_]+)\s*,\s*\{([^}]*)\}"#
        return try matches(of: pattern, in: source).map { groups in
            let constant = groups[1]
            guard let messageName = messageNames[constant] else {
                throw ContractError.unknownMessageConstant(constant)
            }
            return PostSite(messageName: messageName, payloadKeys: objectKeys(in: groups[2]))
        }
    }

    /// `var _MSG_X = "name";` 形式の宣言から JS 定数名 → メッセージ名の対応を作る
    /// (宣言子は同梱 JS の規約に合わせて var / const / let のいずれも受ける)。
    static func messageNamesByJSConstant(in source: String) throws -> [String: String] {
        let pattern = #"(?:var|let|const)\s+(_MSG_[A-Z_]+)\s*=\s*"([A-Za-z]+)""#
        let pairs = try matches(of: pattern, in: source).map { ($0[1], $0[2]) }
        #expect(!pairs.isEmpty, "viewer-bundle.js に _MSG_* 定数の宣言が見つからない")
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    /// オブジェクトリテラルの中身(`href, metaKey: e.metaKey, shiftKey: e.shiftKey`)からキー名を取り出す。
    ///
    /// esbuild は `href: href` を短縮記法 `href` へ畳むため、`key:` 形式だけを見る
    /// 正規表現では取りこぼす。`,` で区切り、`:` の前が識別子ならキーとして拾う
    /// (値の側の断片は識別子にならないので落ちる)。
    static func objectKeys(in body: String) -> Set<String> {
        let identifier = try? NSRegularExpression(pattern: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#)
        let keys = body.split(separator: ",").compactMap { entry -> String? in
            let head = String(entry.split(separator: ":", maxSplits: 1)[0])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(head.startIndex..., in: head)
            guard identifier?.firstMatch(in: head, range: range) != nil else { return nil }
            return head
        }
        return Set(keys)
    }

    /// 正規表現のマッチを、キャプチャグループの文字列配列(index 0 は全体)として返す。
    static func matches(of pattern: String, in text: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0 ..< match.numberOfRanges).map { index in
                guard let groupRange = Range(match.range(at: index), in: text) else { return "" }
                return String(text[groupRange])
            }
        }
    }

    /// `function <name>(...)` が指定した引数の個数で定義されているかを返す。
    ///
    /// 仮引数の**名前**では照合しない。ベンダー(markdown-it / highlight.js /
    /// DOMPurify)を同じ IIFE へバンドルするようになったため、esbuild が名前衝突を
    /// 避けて仮引数を改名する(`appendChunk(text, …)` → `appendChunk(text3, …)`)。
    /// ブリッジの契約は「関数名と引数の個数」であって、バンドル内部で付け替えられる
    /// 識別子ではない。名前で照合すると、無関係な依存追加でここが落ちる。
    static func definesFunction(
        _ source: String, _ name: String, parameterCount: Int
    ) -> Bool {
        let pattern = #"function\s+"# + NSRegularExpression.escapedPattern(for: name)
            + #"\s*\(([^)]*)\)"#
        guard let found = try? matches(of: pattern, in: source) else { return false }
        return found.contains { match in
            let params = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let count = params.isEmpty ? 0 : params.split(separator: ",").count
            return count == parameterCount
        }
    }

    /// `var NAME = <数値>;` 形式の宣言から値を数値として取り出す。
    ///
    /// リテラルの表記を文字列で突き合わせない理由: esbuild は `2.0` を `2` へ
    /// 正規化するため、Swift 側の `\(ZoomStore.maxZoom)`("2.0")とは表記が食い違う。
    /// 表記に合わせて Int() を挟むといった小細工は、閾値の型や桁が変わるたびに
    /// 壊れる。ここで比較したいのは値なので、値として取り出して比べる。
    static func jsNumber(named name: String, in source: String) throws -> Double {
        let pattern = #"(?:var|let|const)\s+"# + name + #"\s*=\s*(-?\d+(?:\.\d+)?)\s*;"#
        let found = try matches(of: pattern, in: source)
        let first = try #require(found.first, "JS 側に \(name) の数値宣言が見つからない")
        return try #require(Double(first[1]), "\(name) の値を数値として読めない: \(first[1])")
    }

    /// 検証対象の JS ソース。viewer-src/ のモジュールではなく、実際に .app へ
    /// 同梱される esbuild 成果物(viewer-bundle.js)を読む。ソースと成果物のズレは
    /// CI の `npm run check:viewer-bundle` が検出する。
    ///
    /// esbuild は文字列リテラルを二重引用符へ正規化し、`href: href` を短縮記法へ
    /// 畳むため、ここで照合するトークンはその形に合わせてある。
    static func viewerBundleSource() throws -> String {
        try String(contentsOf: resourceURL("viewer-bundle.js"), encoding: .utf8)
    }

    /// BefoldKit のリソースバンドルから、ビルド成果物に実際に含まれるリソース URL を返す。
    static func resourceURL(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: name)
        guard let resourceURL = Bundle.befoldKitResources.url(
            forResource: url.deletingPathExtension().lastPathComponent,
            withExtension: url.pathExtension
        ) else {
            throw ContractError.missingResource(name)
        }
        return resourceURL
    }

    enum ContractError: Error {
        case missingResource(String)
        case unknownMessageConstant(String)
    }
}
