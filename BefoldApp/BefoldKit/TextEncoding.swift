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

    /// 静的1回読込(QuickLook 等)でレガシーエンコーディング判定が先頭 sniffLength バイトで
    /// 確定しなかった場合に、全データの代わりに使うフォールバック判定窓の上限。
    /// sniffLength より大きく、かつ 100MB 級ファイルでも即応できる範囲に収める。
    public static let oneShotFallbackScanBytes = 1024 * 1024

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
    /// detectAndDecodeText と同じ2段階フォールバック戦略を共有する。
    public static func detectEncoding(_ data: Data) -> (encoding: String.Encoding, bomLength: Int)? {
        detectWithFallback(data).map { (encoding: $0.encoding, bomLength: $0.bomLength) }
    }

    /// BOM チェック・NUL スキャン・UTF-8 全文デコードの結果。判定窓(sniffWindow)によらず
    /// data 全体から一意に決まるため、フォールバック再試行の対象にならない。
    private static func detectFixedEncoding(
        _ data: Data
    ) -> (encoding: String.Encoding, bomLength: Int, decodedText: String?)? {
        if let bom = detectBOM(data) {
            return (bom.encoding, bom.bomLength, nil)
        }
        let nulCheckWindow = data.prefix(sniffLength)
        if nulCheckWindow.contains(0) {
            let encoding: String.Encoding = looksLittleEndianUTF16(nulCheckWindow)
                ? .utf16LittleEndian : .utf16BigEndian
            return (encoding, 0, nil)
        }
        if let utf8String = String(data: data, encoding: .utf8) {
            return (.utf8, 0, utf8String)
        }
        return nil
    }

    /// detectFixedEncoding で判定できない場合、NSString.stringEncoding によるレガシー
    /// エンコーディング判定を先頭 sniffLength バイトで試み、失敗した場合のみ全データを
    /// 判定窓として再試行する。
    private static func detectWithFallback(
        _ data: Data
    ) -> (encoding: String.Encoding, bomLength: Int, decodedText: String?)? {
        detectFixedEncoding(data)
            ?? detectLegacyEncoding(sniffWindow: data.prefix(sniffLength))
            ?? detectLegacyEncoding(sniffWindow: data)
    }

    /// NSString.stringEncoding によるレガシーエンコーディング判定を sniffWindow に対して行う。
    private static func detectLegacyEncoding(
        sniffWindow: Data
    ) -> (encoding: String.Encoding, bomLength: Int, decodedText: String?)? {
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: sniffWindow, encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        if detected != 0, !usedLossyConversion.boolValue {
            return (String.Encoding(rawValue: detected), 0, nil)
        }
        return nil
    }

    /// BOM 付き UTF-8 / UTF-16 / UTF-32、BOM なし UTF-16、UTF-8、
    /// および Shift_JIS / EUC-JP 等のレガシーエンコーディングを判定して復号する。
    /// エンコーディング・BOM 長の判定は detectWithFallback に委譲する。
    /// いずれの復号にも失敗した場合は nil を返す。
    public static func decodeText(_ data: Data) -> String? {
        detectAndDecodeText(data)?.text
    }

    /// エンコーディング判定と復号を1パスで行う。detectFixedEncoding は判定窓によらず
    /// 結果が変わらないため一度だけ行う。それで判定できない場合は、レガシーエンコーディング
    /// 判定と復号の両方を先頭 sniffLength バイトで試み、判定または復号のいずれかが失敗した
    /// 場合のみ2回目の判定窓(既定は全データ)で再試行する
    /// (sniffWindow がたまたま ASCII のみ等で判定には成功しても、実際のデータを
    /// 正しく復号できないケースがあるため、判定成功だけでなく復号成功も再試行の条件とする)。
    /// fallbackScanLimit を指定すると、2回目の判定窓を全データではなく先頭 fallbackScanLimit
    /// バイトに制限する(静的1回読込で 100MB 級ファイルの全量スキャンを避けるため)。
    /// 復号(decode)自体は判定窓によらず常に全データに対して行われるため、正しさは変わらない。
    static func detectAndDecodeText(
        _ data: Data, fallbackScanLimit: Int? = nil
    ) -> (encoding: String.Encoding, bomLength: Int, text: String)? {
        if let fixed = detectFixedEncoding(data) {
            return decode(data, detected: fixed)
        }
        let fallbackWindow = fallbackScanLimit.map { data.prefix($0) } ?? data
        return decodeUsingLegacyDetection(data, sniffWindow: data.prefix(sniffLength))
            ?? decodeUsingLegacyDetection(data, sniffWindow: fallbackWindow)
    }

    private static func decodeUsingLegacyDetection(
        _ data: Data, sniffWindow: Data
    ) -> (encoding: String.Encoding, bomLength: Int, text: String)? {
        guard let detected = detectLegacyEncoding(sniffWindow: sniffWindow) else { return nil }
        return decode(data, detected: detected)
    }

    private static func decode(
        _ data: Data, detected: (encoding: String.Encoding, bomLength: Int, decodedText: String?)
    ) -> (encoding: String.Encoding, bomLength: Int, text: String)? {
        let payload = data.dropFirst(detected.bomLength)
        guard let decoded = detected.decodedText ?? String(data: payload, encoding: detected.encoding) else {
            return nil
        }
        return (detected.encoding, detected.bomLength, decoded)
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
    /// (LE は奇数位置、BE は偶数位置に NUL が並ぶ)。呼び出し元が判定窓を絞り込む。
    static func looksLittleEndianUTF16(_ data: Data) -> Bool {
        let parity = nulParity(data)
        return parity.odd >= parity.even
    }
}
