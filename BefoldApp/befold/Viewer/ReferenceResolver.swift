// BefoldApp/befold/Viewer/ReferenceResolver.swift
import Foundation

enum ReferenceTarget: Equatable {
    case external(URL)
    case localFile(URL)
    case unsupported
}

enum ReferenceResolver {
    static func resolve(href: String, baseURL: URL) -> ReferenceTarget {
        guard !href.isEmpty, !href.hasPrefix("#") else { return .unsupported }

        if let url = URL(string: href), let scheme = url.scheme {
            switch scheme {
            case "http", "https":
                return .external(url)
            default:
                return .unsupported
            }
        }

        // ローカルパス: 行番号サフィックス (:数字) を除去
        let pathString: String = if let colonRange = href.range(
            of: #":\d+$"#, options: .regularExpression
        ) {
            String(href[..<colonRange.lowerBound])
        } else {
            href
        }

        if pathString.hasPrefix("/") {
            return .localFile(URL(fileURLWithPath: pathString).standardized)
        }

        let baseDir = baseURL.deletingLastPathComponent()
        let resolved = baseDir.appendingPathComponent(pathString).standardized
        return .localFile(resolved)
    }
}
