import Foundation

/// チャンク読み込み・エンコーディング判定で発生しうるエラー。
public enum TextEncodingError: Error, Sendable {
    /// UTF-16 / UTF-32 など、行単位でバイト境界を確定できないエンコーディング。
    case unsupportedForChunking
    /// 検出したエンコーディングでの復号に失敗した。
    case decodeFailed
}

/// テキストのエンコーディング判定・復号ロジックを集約する。
/// FileReading(全量読み込み)と LineChunkReader(チャンク読み込み)の双方から使う。
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
    /// BOM がある場合はその bomLength を、それ以外は 0 を返す
    /// (呼び出し元が復号時にスキップすべきバイト数の単一情報源)。
    /// BOM なしで NUL を含む場合は UTF-16 とみなし、NUL の位置から endian を推定する
    /// (呼び出し元がチャンク読み込みの場合は isChunkableEncoding が事前にこのケースを
    /// 弾くため、この分岐に到達するのは全量読み込み経由のみ)。
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

    /// UTF-8 のバイト列がマルチバイト文字の途中で切れている場合、
    /// 直前の文字境界(先頭バイトの手前)まで末尾を切り詰めて返す。
    /// 末尾の継続バイト(0b10xxxxxx)を遡り、先頭バイトが見つかればそれも落とす
    /// (最大 3+1 バイト)。境界で切れていなければそのまま返す。
    public static func trimIncompleteUTF8Tail(_ data: Data) -> Data {
        var end = data.endIndex
        let maxScan = min(data.count, 4)
        let scanLimit = data.index(data.endIndex, offsetBy: -maxScan)
        while end > scanLimit {
            let byte = data[data.index(before: end)]
            if byte & 0x80 == 0 { break }
            if byte & 0xC0 != 0x80 {
                end = data.index(before: end)
                break
            }
            end = data.index(before: end)
        }
        return data[data.startIndex ..< end]
    }

    /// チャンク末尾のマルチバイト文字境界を保護する汎用メソッド。
    /// UTF-8 は既存のビットパターン走査で高速に処理し、
    /// それ以外のエンコーディングはデコード試行+末尾切り詰めリトライで対処する。
    public static func trimIncompleteTail(_ data: Data, encoding: String.Encoding) -> Data {
        if encoding == .utf8 || encoding == .ascii {
            return trimIncompleteUTF8Tail(data)
        }
        if String(data: data, encoding: encoding) != nil {
            return data
        }
        for trim in 1 ... min(3, data.count) {
            let candidate = data[data.startIndex ..< data.index(data.endIndex, offsetBy: -trim)]
            if String(data: candidate, encoding: encoding) != nil {
                return Data(candidate)
            }
        }
        return data
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
