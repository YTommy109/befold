import Foundation

public enum ReferenceTarget: Equatable, Sendable {
    case external(URL)
    case localFile(URL)
    case unsupported
}

public enum ReferenceResolver {
    public static func resolve(href: String, baseURL: URL) -> ReferenceTarget {
        switch classify(href: href) {
        case let .external(url):
            return .external(url)
        case .unsupported:
            return .unsupported
        case let .local(pathString):
            if pathString.hasPrefix("/") {
                return .localFile(URL(fileURLWithPath: pathString).standardized)
            }
            let baseDir = baseURL.deletingLastPathComponent()
            return .localFile(baseDir.appendingPathComponent(pathString).standardized)
        }
    }

    /// ローカルパスとして解釈できる href のみ、整形済み(fragment・行番号サフィックス除去、
    /// パーセントデコード済み)のパス文字列を返す。外部 URL・未対応スキーム・アンカーは nil。
    public static func localPathString(from href: String) -> String? {
        if case let .local(pathString) = classify(href: href) { return pathString }
        return nil
    }

    // MARK: - 内部分類

    private enum Classified {
        case external(URL)
        case local(String)
        case unsupported
    }

    private static func classify(href: String) -> Classified {
        guard !href.isEmpty, !href.hasPrefix("#") else { return .unsupported }

        if let url = URL(string: href), let scheme = url.scheme {
            switch scheme.lowercased() {
            case "http", "https":
                return .external(url)
            default:
                // URL(string: "notes.md:12") は scheme="notes.md" と解釈される。
                // ドットを含む scheme はファイル名の誤認とみなしローカルパスへ回す。
                if !scheme.contains(".") { return .unsupported }
            }
        }

        // #fragment を除去（クロスドキュメントリンク other.md#section 対応）。
        // パーセントデコードより前に行う。逆順にすると、ファイル名の # をエスケープした
        // href(file%23name.md)がデコードで生の # に戻り、以降を fragment として失う。
        let withoutFragment: String = if let hashIndex = href.firstIndex(of: "#") {
            String(href[..<hashIndex])
        } else {
            href
        }
        let decoded = withoutFragment.removingPercentEncoding ?? withoutFragment

        // 行番号・行列サフィックス (:数字) を繰り返し除去
        let pathString: String = if let colonRange = decoded.range(
            of: #"(?::\d+)+$"#, options: .regularExpression
        ) {
            String(decoded[..<colonRange.lowerBound])
        } else {
            decoded
        }

        guard !pathString.isEmpty else { return .unsupported }
        return .local(pathString)
    }
}
