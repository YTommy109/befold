import Foundation

public enum ReferenceTarget: Equatable, Sendable {
    case external(URL)
    case localFile(URL)
    case unsupported
}

public enum ReferenceResolver {
    public static func resolve(href: String, baseURL: URL) -> ReferenceTarget {
        guard !href.isEmpty, !href.hasPrefix("#") else { return .unsupported }

        let decoded = href.removingPercentEncoding ?? href

        if let url = URL(string: href), let scheme = url.scheme {
            switch scheme.lowercased() {
            case "http", "https":
                return .external(url)
            default:
                // URL(string: "notes.md:12") は scheme="notes.md" と解釈される。
                // ドットを含む scheme はファイル名の誤認とみなしローカルパスへ回す。
                if scheme.contains(".") { break }
                return .unsupported
            }
        }

        // #fragment を除去（クロスドキュメントリンク other.md#section 対応）
        let withoutFragment: String = if let hashIndex = decoded.firstIndex(of: "#") {
            String(decoded[..<hashIndex])
        } else {
            decoded
        }

        // 行番号・行列サフィックス (:数字) を繰り返し除去
        let pathString: String = if let colonRange = withoutFragment.range(
            of: #"(?::\d+)+$"#, options: .regularExpression
        ) {
            String(withoutFragment[..<colonRange.lowerBound])
        } else {
            withoutFragment
        }

        guard !pathString.isEmpty else { return .unsupported }

        if pathString.hasPrefix("/") {
            return .localFile(URL(fileURLWithPath: pathString).standardized)
        }

        let baseDir = baseURL.deletingLastPathComponent()
        let resolved = baseDir.appendingPathComponent(pathString).standardized
        return .localFile(resolved)
    }
}
