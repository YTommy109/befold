import Foundation

/// エンコーディング判定・復号で発生しうるエラー。
public enum TextEncodingError: Error, Sendable {
    /// 検出したエンコーディングでの復号に失敗した。
    case decodeFailed
}

/// テキストのエンコーディング判定・復号ロジックを集約する。
public enum TextEncoding: Sendable {
    /// バイナリ判定・エンコーディング判定に見る先頭バイト数。
    public static let sniffLength = 8192

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

    /// BOM またはヒューリスティックでエンコーディングを推定する(復号はしない)。
    /// BOM がある場合はその bomLength を、それ以外は 0 を返す
    /// (呼び出し元が復号時にスキップすべきバイト数の単一情報源)。
    /// BOM なしで NUL を含む場合は UTF-16 とみなし、NUL の位置から endian を推定する。
    public static func detectEncoding(_ data: Data) -> (encoding: String.Encoding, bomLength: Int)? {
        if let bom = detectBOM(data) {
            return bom
        }
        if data.prefix(sniffLength).contains(0) {
            let encoding: String.Encoding = looksLittleEndianUTF16(data) ? .utf16LittleEndian : .utf16BigEndian
            return (encoding, 0)
        }
        if String(data: data, encoding: .utf8) != nil {
            return (.utf8, 0)
        }
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data, encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        if detected != 0, !usedLossyConversion.boolValue { return (String.Encoding(rawValue: detected), 0) }
        return nil
    }

    /// BOM 付き UTF-8 / UTF-16 / UTF-32、BOM なし UTF-16、UTF-8、
    /// および Shift_JIS / EUC-JP 等のレガシーエンコーディングを判定して復号する。
    /// エンコーディング・BOM 長の判定は detectEncoding に委譲する。
    /// いずれの復号にも失敗した場合は nil を返す。
    public static func decodeText(_ data: Data) -> String? {
        guard let detected = detectEncoding(data) else { return nil }
        return String(data: data.dropFirst(detected.bomLength), encoding: detected.encoding)
    }

    /// データ中の NUL バイトを偶数位置・奇数位置別に数える。
    /// UTF-16 の endian 推定・バイナリ判定など、NUL の位置的偏りを見る用途で共有する。
    static func nulParity(_ data: Data) -> (even: Int, odd: Int) {
        var evenNul = 0, oddNul = 0
        for (index, byte) in data.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) { evenNul += 1 } else { oddNul += 1 }
        }
        return (evenNul, oddNul)
    }

    /// BOM なし UTF-16 の endian を NUL の位置から推定する
    /// (LE は奇数位置、BE は偶数位置に NUL が並ぶ)。
    static func looksLittleEndianUTF16(_ data: Data) -> Bool {
        let parity = nulParity(data.prefix(sniffLength))
        return parity.odd >= parity.even
    }
}
