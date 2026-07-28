import Foundation

/// charset 宣言の無い HTML を WKWebView へ直接ロードすると、WebKit が既定エンコーディング
/// (日本語環境では Latin-1/Shift_JIS 等)を誤推定して UTF-8 バイトを二重解釈し文字化けする。
///
/// 宣言の有無を判定し、無い場合だけ `TextEncoding` で実エンコーディングを判定して UTF-8 文字列へ
/// 正規化する。宣言がある(BOM・`<meta charset>`)場合は WebKit の解釈に任せてよいため、
/// 呼び出し元は従来どおり `loadFileURL`(相対リソースの読み取り許可つき)で読ませられる。
public enum HTMLCharsetNormalizer {
    /// HTML の encoding 宣言があるか。UTF-8/16/32 の BOM、または先頭 1024 バイト内の
    /// `charset=` を宣言とみなす。HTML 仕様で encoding 宣言は文書先頭 1024 バイト以内に
    /// 置くと定められているため、走査もその範囲に限る。
    public static func hasCharsetDeclaration(_ data: Data) -> Bool {
        if TextEncoding.detectBOM(data) != nil { return true }
        // 判定に見るのは「charset=」というバイト列の有無だけなので、必ず文字列化できる
        // isoLatin1 で先頭 1024 バイトをデコードして探す(本文の実エンコーディングは問わない)。
        let head = String(data: data.prefix(1024), encoding: .isoLatin1) ?? ""
        return head.range(of: "charset=", options: .caseInsensitive) != nil
    }

    /// charset 宣言が無ければ実エンコーディングを判定して UTF-8 文字列へ正規化して返す。
    /// 宣言があれば nil を返す(呼び出し元は `loadFileURL` で相対リソースごと読ませる)。
    /// エンコーディングを判定できない場合も nil(従来の直接ロードにフォールバックさせる)。
    public static func utf8NormalizedHTML(for data: Data) -> String? {
        guard !hasCharsetDeclaration(data) else { return nil }
        return TextEncoding.decodeText(data)
    }
}
