// BefoldApp/befold/Viewer/MarkdownImageEmbedder.swift
import Foundation

/// markdown 本文中の ![alt](path) が指すローカル画像を base64 data URI に差し替える
/// レンダリング前プリプロセス。viewer.html の CSP は img-src 'self' data: のため、
/// ローカルパスのままでは画像を読めない(data URI は許可済みなので CSP 変更が不要)。
/// リモート URL・読込失敗・非対応拡張子は原文のまま残す。
enum MarkdownImageEmbedder {
    /// 埋め込み対象の拡張子 → MIME タイプ。画像ファイル単体表示の対応表に加えて SVG も
    /// 対象にする(<img> 経由の SVG は画像モードで扱われスクリプトが実行されないため安全)。
    static let imageExtensionMimeTypes: [String: String] =
        FileType.imageExtensionMimeTypes.merging(["svg": "image/svg+xml"]) { current, _ in current }

    /// 1 画像あたりのサイズ上限。バイナリ表示と同じ上限を単一情報源から参照する。
    static let defaultMaxImageSizeBytes = ContentLoader.maxBinaryFileSizeBytes

    // Regex は Sendable でないため、strict concurrency 下では static 格納プロパティに
    // できず、各関数内のローカル定数として生成する。

    /// 生成済み data URI のキャッシュ。ライブリロードで markdown 本文が変わるたびに、
    /// 未変更の画像まで同期読込・base64 化してメインスレッドを塞ぐのを避ける。
    private static let cache = DataURICache()

    /// markdown 内のローカル画像参照を data URI に差し替えた文字列を返す。
    /// - Parameters:
    ///   - markdown: 元の markdown 本文。
    ///   - baseURL: 相対パスの解決基準となる markdown ファイルの URL。
    ///   - maxImageSizeBytes: これを超えるサイズの画像は差し替えない。
    static func embedLocalImages(
        in markdown: String,
        baseURL: URL,
        maxImageSizeBytes: Int = defaultMaxImageSizeBytes
    ) -> String {
        // 画像記法が無ければ行分割・正規表現走査ごと省く。
        guard markdown.contains("![") else { return markdown }
        // フェンスコードブロックの開始/終了行(先頭 0〜3 スペース + ``` または ~~~)。
        let fencePattern = #/^ {0,3}(`{3,}|~{3,})/#
        var openFenceMarker: Character?
        let lines = markdown.components(separatedBy: "\n").map { line in
            if let match = line.firstMatch(of: fencePattern) {
                let marker = match.1.first
                if openFenceMarker == nil {
                    openFenceMarker = marker
                } else if openFenceMarker == marker {
                    openFenceMarker = nil
                }
                return line
            }
            guard openFenceMarker == nil else { return line }
            return embedImages(inLine: line, baseURL: baseURL, maxImageSizeBytes: maxImageSizeBytes)
        }
        return lines.joined(separator: "\n")
    }

    /// 1 行内の画像記法を差し替える。インラインコードスパン内は対象外。
    private static func embedImages(
        inLine line: String, baseURL: URL, maxImageSizeBytes: Int
    ) -> String {
        // ![alt](path) / ![alt](path "title")。パスは空白・閉じ括弧を含まない前提
        // (空白を含むパスはパーセントエンコードで表現する)。
        let imagePattern = #/!\[([^\]]*)\]\(\s*([^)\s]+)(\s+"[^"]*"|\s+'[^']*')?\s*\)/#
        // インラインコードスパン(`...` / ``...``)。
        let inlineCodePattern = #/(`+).*?\1/#

        let codeSpans = line.ranges(of: inlineCodePattern)
        var output = ""
        var cursor = line.startIndex
        for match in line.matches(of: imagePattern) {
            guard !codeSpans.contains(where: { $0.overlaps(match.range) }),
                  let dataURI = dataURI(
                      forPath: String(match.2), baseURL: baseURL,
                      maxImageSizeBytes: maxImageSizeBytes
                  )
            else { continue }
            let title = match.3.map(String.init) ?? ""
            output += line[cursor ..< match.range.lowerBound]
            output += "![\(match.1)](\(dataURI)\(title))"
            cursor = match.range.upperBound
        }
        output += line[cursor...]
        return output
    }

    /// ローカル画像パスを data URI に変換する。対象外・失敗時は nil。
    /// 更新日時・サイズが前回と一致すればキャッシュ済みの data URI を返す。
    private static func dataURI(
        forPath path: String, baseURL: URL, maxImageSizeBytes: Int
    ) -> String? {
        guard case let .localFile(url) = ReferenceResolver.resolve(href: path, baseURL: baseURL),
              let mimeType = imageExtensionMimeTypes[url.pathExtension.lowercased()],
              let values = try? url.resourceValues(
                  forKeys: [.fileSizeKey, .contentModificationDateKey]
              ),
              let size = values.fileSize,
              size <= maxImageSizeBytes
        else { return nil }
        let mtime = values.contentModificationDate
        if let cached = cache.uri(for: url, size: size, mtime: mtime) { return cached }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let uri = "data:\(mimeType);base64,\(data.base64EncodedString())"
        cache.store(uri, for: url, size: size, mtime: mtime)
        return uri
    }

    /// 生成済み data URI を (更新日時, サイズ) で検証しつつ保持する内部キャッシュ。
    /// 内部 NSLock で排他するため `@unchecked Sendable`。base64 文字列の総量が
    /// 上限を超えたら全消去し、メモリの無制限な肥大化を防ぐ(LRU は過剰)。
    private final class DataURICache: @unchecked Sendable {
        private struct Entry {
            let size: Int
            let mtime: Date?
            let uri: String
        }

        /// 保持する data URI 文字列の総バイト数上限(約 128MB)。
        private static let maxTotalBytes = 128 * 1024 * 1024

        private let lock = NSLock()
        private var entries: [URL: Entry] = [:]
        private var totalBytes = 0

        /// 更新日時とサイズが一致するキャッシュ済み data URI を返す。無ければ nil。
        func uri(for url: URL, size: Int, mtime: Date?) -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[url], entry.size == size, entry.mtime == mtime else {
                return nil
            }
            return entry.uri
        }

        /// data URI を保存する。総量が上限を超えたらキャッシュを全消去する。
        func store(_ uri: String, for url: URL, size: Int, mtime: Date?) {
            lock.lock()
            defer { lock.unlock() }
            if let existing = entries[url] {
                totalBytes -= existing.uri.utf8.count
            }
            entries[url] = Entry(size: size, mtime: mtime, uri: uri)
            totalBytes += uri.utf8.count
            if totalBytes > Self.maxTotalBytes {
                entries.removeAll()
                totalBytes = 0
            }
        }
    }
}
