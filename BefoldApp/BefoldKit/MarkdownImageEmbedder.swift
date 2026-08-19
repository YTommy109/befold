import Foundation

/// markdown 本文中の ![alt](path) と inline HTML の <img src="path"> が指すローカル画像を
/// base64 data URI に差し替えるレンダリング前プリプロセス。viewer.html の CSP は
/// img-src 'self' data: のため、ローカルパスのままでは画像を読めない
/// (data URI は許可済みなので CSP 変更が不要)。
/// リモート URL・読込失敗・非対応拡張子は原文のまま残す。
///
/// inline HTML も対象にするのは、GitHub 向けの README が中央寄せ・幅指定・表内配置のために
/// <img> を使わざるを得ず(markdown 記法では表現できない)、そのままでは画像が 1 枚も
/// 出ないため(TASK-524)。差し替えるのは src 属性の値だけで、他の属性は原文のまま残す。
public struct MarkdownImageEmbedder: Sendable {
    /// 埋め込み対象の拡張子 → MIME タイプ。画像ファイル単体表示の対応表に加えて SVG も
    /// 対象にする(<img> 経由の SVG は画像モードで扱われスクリプトが実行されないため安全)。
    public static let imageExtensionMimeTypes: [String: String] =
        FileType.imageExtensionMimeTypes.merging(["svg": "image/svg+xml"]) { current, _ in current }

    /// 1 画像あたりのサイズ上限。バイナリ表示と同じ上限を単一情報源から参照する。
    public static let defaultMaxImageSizeBytes = ContentLoader.maxFileSizeBytes

    /// <img> タグの走査前に行う安価な絞り込み。正規表現より先にこれで弾く。
    /// 大文字の <IMG も HTML として有効なため大文字小文字を無視して探す。
    private static func containsImageTag(_ text: String) -> Bool {
        text.range(of: "<img", options: .caseInsensitive) != nil
    }

    // Regex は Sendable でないため、strict concurrency 下では static 格納プロパティに
    // できず、各関数内のローカル定数として生成する。

    /// 本番で使う共有インスタンス。data URI キャッシュはインスタンスが持つため、
    /// ロード時のウォームアップと render 直前の差し替えは必ずこの 1 個を経由すること
    /// (別インスタンスを作るとキャッシュが共有されず、画像を毎回読み直す)。
    public static let shared = MarkdownImageEmbedder()

    private let fileReader: any FileReading

    /// 生成済み data URI のキャッシュ。ライブリロードで markdown 本文が変わるたびに、
    /// 未変更の画像まで同期読込・base64 化してメインスレッドを塞ぐのを避ける。
    /// インスタンスごとに持つため、テストは自前のインスタンスを作れば互いに干渉しない。
    private let cache = DataURICache()

    /// - Parameter fileReader: 画像のサイズ・更新日時・内容の取得元。
    public init(fileReader: any FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    /// markdown 内のローカル画像参照を data URI に差し替えた文字列を返す。
    /// - Parameters:
    ///   - markdown: 元の markdown 本文。
    ///   - baseURL: 相対パスの解決基準となる markdown ファイルの URL。
    ///   - maxImageSizeBytes: これを超えるサイズの画像は差し替えない。
    public func embedLocalImages(
        in markdown: String,
        baseURL: URL,
        maxImageSizeBytes: Int = defaultMaxImageSizeBytes
    ) -> String {
        // 画像記法も <img> も無ければ行分割・正規表現走査ごと省く。
        guard markdown.contains("![") || Self.containsImageTag(markdown) else {
            return markdown
        }
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

    /// 1 行内の画像参照(markdown 記法と inline HTML の <img>)を差し替える。
    /// インラインコードスパン内は対象外。
    ///
    /// 記法ごとに組み立て直さず「パス部分の範囲 → data URI」の置換列に落として 1 度で
    /// 組み立てる。こうすると alt・title・その他の属性は原文のまま残り、記法が増えても
    /// コードスパン除外と再構築のロジックを共有できる。
    private func embedImages(
        inLine line: String, baseURL: URL, maxImageSizeBytes: Int
    ) -> String {
        // インラインコードスパン(`...` / ``...``)。
        let inlineCodePattern = #/(`+).*?\1/#
        let codeSpans = line.ranges(of: inlineCodePattern)

        var replacements = pathRanges(inMarkdownNotationOf: line, excluding: codeSpans)
        replacements += pathRanges(inImageTagsOf: line, excluding: codeSpans)
        // 記法ごとに別々に集めるため、位置順に並べ直してから前から組み立てる。
        replacements.sort { $0.lowerBound < $1.lowerBound }

        var output = ""
        var cursor = line.startIndex
        for pathRange in replacements {
            // 万一 2 つの記法の範囲が重なったら、先に採った側を優先して後続を捨てる。
            guard pathRange.lowerBound >= cursor,
                  let dataURI = dataURI(
                      forPath: String(line[pathRange]), baseURL: baseURL,
                      maxImageSizeBytes: maxImageSizeBytes
                  )
            else { continue }
            output += line[cursor ..< pathRange.lowerBound]
            output += dataURI
            cursor = pathRange.upperBound
        }
        output += line[cursor...]
        return output
    }

    /// markdown 記法 ![alt](path) / ![alt](path "title") のパス部分の範囲を返す。
    private func pathRanges(
        inMarkdownNotationOf line: String, excluding codeSpans: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        // パスは空白・閉じ括弧を含まない前提(空白を含むパスはパーセントエンコードで表現する)。
        let imagePattern = #/!\[[^\]]*\]\(\s*([^)\s]+)(?:\s+"[^"]*"|\s+'[^']*')?\s*\)/#
        guard line.contains("![") else { return [] }
        return line.matches(of: imagePattern)
            .filter { match in !codeSpans.contains { $0.overlaps(match.range) } }
            .map { $0.1.startIndex ..< $0.1.endIndex }
    }

    /// inline HTML の <img ...> の src 属性値の範囲を返す。
    ///
    /// タグ本体と src 属性値を 2 段階で取るのは、属性の順序(width が src より前など)と
    /// クォート種別(ダブル / シングル / 裸)の組み合わせを 1 本の正規表現に押し込むと
    /// 網羅漏れが起きるため。タグ本体のパターンはクォート内を読み飛ばすので、
    /// alt="a > b" のように属性値へ > が現れてもタグ末尾を誤認しない。
    private func pathRanges(
        inImageTagsOf line: String, excluding codeSpans: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        // チャンク追記のたびに全行を走るため、<img> を含まない行では正規表現を走らせない。
        guard Self.containsImageTag(line) else { return [] }
        let imgTagPattern = #/(?i)<img\b(?:[^>"']|"[^"]*"|'[^']*')*>/#
        let srcPattern = #/(?i)\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/#

        return line.matches(of: imgTagPattern).compactMap { tagMatch in
            guard !codeSpans.contains(where: { $0.overlaps(tagMatch.range) }),
                  let src = line[tagMatch.range].firstMatch(of: srcPattern),
                  let value = src.1 ?? src.2 ?? src.3,
                  !value.isEmpty
            else { return nil }
            return value.startIndex ..< value.endIndex
        }
    }

    /// ローカル画像パスを data URI に変換する。対象外・失敗時は nil。
    /// 更新日時・サイズが前回と一致すればキャッシュ済みの data URI を返す。
    private func dataURI(
        forPath path: String, baseURL: URL, maxImageSizeBytes: Int
    ) -> String? {
        guard case let .localFile(url) = ReferenceResolver.resolve(href: path, baseURL: baseURL),
              let mimeType = Self.imageExtensionMimeTypes[url.pathExtension.lowercased()],
              let size = fileReader.fileSize(at: url),
              size <= maxImageSizeBytes
        else { return nil }
        let mtime = fileReader.modificationDate(at: url)
        if let cached = cache.uri(for: url, size: size, mtime: mtime) { return cached }
        guard let data = try? fileReader.readData(from: url) else { return nil }
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
