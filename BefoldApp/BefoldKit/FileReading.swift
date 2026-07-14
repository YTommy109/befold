import Foundation

/// ファイルの存在確認と内容読み込みを抽象化する(テストでの差し替え用)。
public protocol FileReading: Sendable {
    func fileExists(at url: URL) -> Bool
    func readString(from url: URL) throws -> String
    func readData(from url: URL) throws -> Data
    /// テキストとして扱えない内容(バイナリ)かどうかを判定する。
    func isBinary(at url: URL) -> Bool
    /// ファイルのバイトサイズ。取得できない場合は nil。
    func fileSize(at url: URL) -> Int?
}

/// FileManager / String(contentsOf:) による標準実装。
public struct DefaultFileReader: FileReading {
    public init() {}

    /// バイナリ判定・エンコーディング判定に見る先頭バイト数。
    private static let binarySniffLength = 8192

    /// BOM なし UTF-16 とみなす NUL パリティ偏りの許容比。
    /// 少数側 / 多数側の NUL 数がこの比未満なら、NUL が偶数位置か奇数位置の
    /// 一方にほぼ揃っており UTF-16 テキストと判断する
    /// (実バイナリは NUL が散在し、この比は大きくなる)。
    private static let utf16NulParitySkewRatio = 0.1

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func fileSize(at url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
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
        guard let data = try? handle.read(upToCount: Self.binarySniffLength) else { return false }
        // NUL を含まなければテキスト(UTF-8 など)。
        guard data.contains(0) else { return false }
        // UTF-16 / UTF-32 の BOM があればテキスト。
        if Self.hasUnicodeBOM(data) { return false }
        // BOM なしでも NUL が片側の位置に偏っていれば UTF-16 テキストとみなす。
        if Self.looksLikeUTF16(data) { return false }
        return true
    }

    /// 先頭バイト列から BOM を検出し、対応するエンコーディングと BOM 長を返す。
    /// UTF-32 の BOM(4 バイト)は UTF-16 LE と先頭が同じなので先に判定する。
    private static func detectBOM(_ data: Data) -> (encoding: String.Encoding, bomLength: Int)? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 4 {
            if bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF {
                return (.utf32BigEndian, 4)
            }
            if bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0x00, bytes[3] == 0x00 {
                return (.utf32LittleEndian, 4)
            }
        }
        if bytes.count >= 2 {
            if bytes[0] == 0xFE, bytes[1] == 0xFF { return (.utf16BigEndian, 2) }
            if bytes[0] == 0xFF, bytes[1] == 0xFE { return (.utf16LittleEndian, 2) }
        }
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return (.utf8, 3)
        }
        return nil
    }

    /// BOM 付き UTF-8 / UTF-16 / UTF-32、および BOM なし UTF-16 を判定して復号する。
    /// いずれの復号にも失敗した場合は nil を返す。
    private static func decodeUnicodeText(_ data: Data) -> String? {
        if let bom = detectBOM(data) {
            return String(data: data.dropFirst(bom.bomLength), encoding: bom.encoding)
        }
        // BOM なしで NUL を含めば UTF-16 とみなし、NUL の位置から endian を推定する。
        // NUL の有無は isBinary と同じ先頭 8KB 窓で判定し、判定窓のずれによる
        // 誤復号(先頭は純テキストで後方に NUL を含む UTF-8 の UTF-16 誤解釈)を防ぐ。
        if data.prefix(binarySniffLength).contains(0) {
            let encoding: String.Encoding = looksLittleEndianUTF16(data)
                ? .utf16LittleEndian
                : .utf16BigEndian
            return String(data: data, encoding: encoding)
        }
        // BOM なし・NUL なしは UTF-8 として復号を試みる。
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // UTF-8 復号に失敗した場合、NSString のヒューリスティックで
        // Shift_JIS / EUC-JP などのエンコーディングを推定する。
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data,
            encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        if detected != 0, let result = convertedString {
            return result as String
        }
        return nil
    }

    /// UTF-8 / UTF-16 / UTF-32 の BOM を検出する。
    private static func hasUnicodeBOM(_ data: Data) -> Bool {
        detectBOM(data) != nil
    }

    /// NUL バイトが偶数位置・奇数位置のどちらか一方にほぼ偏っていれば
    /// BOM なし UTF-16 テキストとみなす(実バイナリは NUL が散在する)。
    private static func looksLikeUTF16(_ data: Data) -> Bool {
        let (evenNul, oddNul) = nulCountsByParity(data)
        let majority = max(evenNul, oddNul)
        guard majority > 0 else { return false }
        let minority = min(evenNul, oddNul)
        return Double(minority) / Double(majority) < utf16NulParitySkewRatio
    }

    /// BOM なし UTF-16 の endian を NUL の位置から推定する
    /// (LE は奇数位置、BE は偶数位置に NUL が並ぶ)。
    private static func looksLittleEndianUTF16(_ data: Data) -> Bool {
        let (evenNul, oddNul) = nulCountsByParity(data.prefix(binarySniffLength))
        return oddNul >= evenNul
    }

    /// 偶数位置・奇数位置それぞれの NUL バイト数を数える。
    private static func nulCountsByParity(_ data: some Sequence<UInt8>) -> (even: Int, odd: Int) {
        var evenNul = 0
        var oddNul = 0
        for (index, byte) in data.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) { evenNul += 1 } else { oddNul += 1 }
        }
        return (evenNul, oddNul)
    }
}
