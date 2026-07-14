import Foundation

/// チャンク読み込み・エンコーディング判定で発生しうるエラー。
public enum TextEncodingError: Error {
    /// UTF-16 / UTF-32 など、行単位でバイト境界を確定できないエンコーディング。
    case unsupportedForChunking
    /// 検出したエンコーディングでの復号に失敗した。
    case decodeFailed
}

/// テキストのエンコーディング判定・復号ロジックを集約する。
/// FileReading(全量読み込み)と LineChunkReader(チャンク読み込み)の双方から使う。
public enum TextEncoding {
    /// バイナリ判定・エンコーディング判定に見る先頭バイト数。
    static let sniffLength = 8192

    /// 先頭バイト列から BOM を検出し、対応するエンコーディングと BOM 長を返す。
    /// UTF-32 の BOM(4 バイト)は UTF-16 LE と先頭が同じなので先に判定する。
    public static func detectBOM(_ data: Data) -> (encoding: String.Encoding, bomLength: Int)? {
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

    /// 行単位でのチャンク分割が可能なエンコーディングかを判定する。
    /// UTF-16 / UTF-32 は改行が複数バイトで表され行境界をバイト位置だけで
    /// 確定できないため不可。BOM なしで NUL を含む場合も不可とする。
    public static func isChunkableEncoding(_ data: Data) -> Bool {
        if let bom = detectBOM(data) {
            switch bom.encoding {
            case .utf16BigEndian, .utf16LittleEndian,
                 .utf32BigEndian, .utf32LittleEndian:
                return false
            default:
                return true
            }
        }
        let sniffWindow = data.prefix(sniffLength)
        return !sniffWindow.contains(0)
    }

    /// BOM またはヒューリスティックでエンコーディングを推定する(復号はしない)。
    public static func detectEncoding(_ data: Data) -> String.Encoding? {
        if let bom = detectBOM(data) {
            return bom.encoding
        }
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data, encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        if detected != 0 { return String.Encoding(rawValue: detected) }
        return nil
    }

    /// BOM 付き UTF-8 / UTF-16 / UTF-32、BOM なし UTF-16、UTF-8、
    /// および Shift_JIS / EUC-JP 等のレガシーエンコーディングを判定して復号する。
    /// いずれの復号にも失敗した場合は nil を返す。
    public static func decodeText(_ data: Data) -> String? {
        if let bom = detectBOM(data) {
            return String(data: data.dropFirst(bom.bomLength), encoding: bom.encoding)
        }
        // BOM なしで NUL を含めば UTF-16 とみなし、NUL の位置から endian を推定する。
        if data.prefix(sniffLength).contains(0) {
            let encoding: String.Encoding = looksLittleEndianUTF16(data)
                ? .utf16LittleEndian : .utf16BigEndian
            return String(data: data, encoding: encoding)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data, encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        if detected != 0, let result = convertedString {
            return result as String
        }
        return nil
    }

    /// BOM なし UTF-16 の endian を NUL の位置から推定する
    /// (LE は奇数位置、BE は偶数位置に NUL が並ぶ)。
    static func looksLittleEndianUTF16(_ data: Data) -> Bool {
        let window = data.prefix(sniffLength)
        var evenNul = 0, oddNul = 0
        for (index, byte) in window.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) { evenNul += 1 } else { oddNul += 1 }
        }
        return oddNul >= evenNul
    }
}
