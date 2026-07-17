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
    /// detectAndDecodeText と同じ2段階フォールバック戦略を共有する。
    public static func detectEncoding(_ data: Data) -> (encoding: String.Encoding, bomLength: Int)? {
        detectWithFallback(data).map { (encoding: $0.encoding, bomLength: $0.bomLength) }
    }

    /// 先頭 sniffLength バイトでの判定を試み、失敗した場合のみ全データを判定窓として再試行する。
    private static func detectWithFallback(
        _ data: Data
    ) -> (encoding: String.Encoding, bomLength: Int, decodedText: String?)? {
        detectEncodingAndDecode(data, sniffWindow: data.prefix(sniffLength))
            ?? detectEncodingAndDecode(data, sniffWindow: data)
    }

    /// エンコーディング判定と同時に、判定過程で得られた復号結果があれば併せて返す。
    /// BOM なし UTF-8 の判定は検証のため一度全文デコードするため、その結果を
    /// decodedText として持ち帰り、呼び出し元での再デコードを避ける。
    /// レガシーエンコーディング判定(NSString.stringEncoding)は sniffWindow に対して行う
    /// (既定は先頭 sniffLength バイト、フォールバック時は全データ)。
    /// NUL 判定のみは sniffWindow の広さによらず常に先頭 sniffLength バイトに限定する
    /// (全データを NUL 判定に使うと、8KB 以降にのみ NUL を含むレガシーエンコーディングの
    /// ファイルが UTF-16 と誤判定されるため)。
    private static func detectEncodingAndDecode(
        _ data: Data, sniffWindow: Data
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
    /// エンコーディング・BOM 長の判定は detectEncodingAndDecode に委譲する。
    /// いずれの復号にも失敗した場合は nil を返す。
    public static func decodeText(_ data: Data) -> String? {
        detectAndDecodeText(data)?.text
    }

    /// エンコーディング判定と復号を1パスで行う。判定過程で全文デコード済みの場合は
    /// その結果を再利用し、判定結果とともに返す。
    /// 先頭 sniffLength バイトのみでの判定・復号が失敗した場合(判定に使ったプレフィックスが
    /// 実データを代表していない、あるいはプレフィックス末尾でマルチバイト文字が
    /// 途切れているケース)は、全データを判定窓として再試行する。
    /// このフォールバックは失敗時にのみ全文走査するため、通常系の高速性は変わらない。
    /// detectEncoding と同じ「先頭 sniffLength バイト→失敗時のみ全データ」という
    /// 2段階フォールバック戦略を、復号の成否まで含めて適用する。
    static func detectAndDecodeText(_ data: Data) -> (encoding: String.Encoding, bomLength: Int, text: String)? {
        if let result = decodeUsingDetection(data, sniffWindow: data.prefix(sniffLength)) {
            return result
        }
        return decodeUsingDetection(data, sniffWindow: data)
    }

    private static func decodeUsingDetection(
        _ data: Data, sniffWindow: Data
    ) -> (encoding: String.Encoding, bomLength: Int, text: String)? {
        guard let detected = detectEncodingAndDecode(data, sniffWindow: sniffWindow) else { return nil }
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
