import Foundation

/// ファイルの存在確認と内容読み込みを抽象化する(テストでの差し替え用)。
public protocol FileReading: Sendable {
    func fileExists(at url: URL) -> Bool
    /// 存在し、かつディレクトリである。
    func isDirectory(at url: URL) -> Bool
    /// 存在し、かつ通常ファイル(ディレクトリでない)。
    func isExistingFile(at url: URL) -> Bool
    func readString(from url: URL) throws -> String
    func readData(from url: URL) throws -> Data
    /// テキストとして扱えない内容(バイナリ)かどうかを判定する。
    func isBinary(at url: URL) -> Bool
    /// ファイルのバイトサイズ。取得できない場合は nil。
    func fileSize(at url: URL) -> Int?
    /// ファイルの最終更新日時。取得できない場合は nil。
    /// サイズだけでは検出できない「同サイズでの内容変更」をキャッシュ無効化に使う。
    func modificationDate(at url: URL) -> Date?
}

/// FileManager / String(contentsOf:) による標準実装。
public struct DefaultFileReader: FileReading {
    public init() {}

    /// BOM なし UTF-16 とみなす NUL パリティ偏りの許容比。
    /// 少数側 / 多数側の NUL 数がこの比未満なら、NUL が偶数位置か奇数位置の
    /// 一方にほぼ揃っており UTF-16 テキストと判断する
    /// (実バイナリは NUL が散在し、この比は大きくなる)。
    private static let utf16NulParitySkewRatio = 0.1

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(at url: URL) -> Bool {
        Self.existence(of: url).isDirectory
    }

    public func isExistingFile(at url: URL) -> Bool {
        let existence = Self.existence(of: url)
        return existence.exists && !existence.isDirectory
    }

    /// 存在確認とディレクトリ判定を 1 度の FileManager 呼び出しで返す。
    /// ObjCBool の取り回しはここ 1 箇所に集約する。
    private static func existence(of url: URL) -> (exists: Bool, isDirectory: Bool) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return (exists, isDir.boolValue)
    }

    public func fileSize(at url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    public func modificationDate(at url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    public func readData(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func readString(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        // BOM 付き UTF-8 / UTF-16 / UTF-32、BOM なし UTF-16、UTF-8、
        // および Shift_JIS / EUC-JP 等のレガシーエンコーディングを判定して復号する。
        // String(contentsOf:usedEncoding:) は BOM なし UTF-16 を誤ったエンコーディングで
        // 復号して文字化けした文字列を返す(エラーを投げない)ため、自前で判定する。
        if let decoded = Self.decodeUnicodeText(data) {
            return decoded
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// 先頭 8KB を読み、テキストとして解釈できない内容ならバイナリと判定する。
    /// NUL バイトを含んでいても、UTF-16 / UTF-32 の BOM があるか、NUL が
    /// 片側の位置に規則的に並ぶ場合は UTF-16 テキストとみなしてテキスト扱いにする。
    /// ファイルを開けない場合はテキスト扱い(false)とし、readString 側の
    /// エラー処理に委ねる。
    public func isBinary(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: TextEncoding.sniffLength) else { return false }
        // NUL を含まなければテキスト(UTF-8 など)。
        guard data.contains(0) else { return false }
        // UTF-16 / UTF-32 の BOM があればテキスト。
        if TextEncoding.detectBOM(data) != nil { return false }
        // BOM なしでも NUL が片側の位置に偏っていれば UTF-16 テキストとみなす。
        if Self.looksLikeUTF16(data) { return false }
        return true
    }

    /// BOM 付き UTF-8 / UTF-16 / UTF-32、BOM なし UTF-16、UTF-8、
    /// および Shift_JIS / EUC-JP 等を判定して復号する。復号に失敗した場合は nil。
    private static func decodeUnicodeText(_ data: Data) -> String? {
        TextEncoding.decodeText(data)
    }

    /// NUL バイトが偶数位置・奇数位置のどちらか一方にほぼ偏っていれば
    /// BOM なし UTF-16 テキストとみなす(実バイナリは NUL が散在する)。
    private static func looksLikeUTF16(_ data: Data) -> Bool {
        let parity = TextEncoding.nulParity(data)
        let majority = max(parity.even, parity.odd)
        guard majority > 0 else { return false }
        let minority = min(parity.even, parity.odd)
        return Double(minority) / Double(majority) < utf16NulParitySkewRatio
    }
}
