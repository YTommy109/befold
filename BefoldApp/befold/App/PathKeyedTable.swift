import BefoldKit
import Foundation

/// メモリ上の「正規化パス → 値」表。`PathKeyedDictionary` と同じキーの規約
/// （`normalizedPathKey`）と rename 時のキー付け替えを、**永続化せずに**提供する。
///
/// `PathKeyedDictionary` を土台に載せ替えないのは、「メモリと UserDefaults の
/// どちらが真実か」という新しい不変条件を作らないため。あちらは全ウィンドウ共有の
/// `PerFileStateStore` が使う永続の器で、こちらは窓の生存期間だけの器。重なるのは
/// 辞書操作 3 行だけなので、共通化より分離を採る。
struct PathKeyedTable<Value> {
    private var values: [String: Value] = [:]

    init() {}

    /// 指定ファイルの値を返す。記憶が無ければ nil。
    func value(for url: URL) -> Value? {
        values[url.normalizedPathKey]
    }

    /// 指定ファイルの値を記憶する。
    mutating func setValue(_ value: Value, for url: URL) {
        values[url.normalizedPathKey] = value
    }

    /// ファイルの rename / move に伴い、旧パスの値を新パスへ引き継ぐ。
    /// 旧パスに記憶が無ければ何もしない。移行後は旧キーを削除する。
    mutating func migrateValue(from oldURL: URL, to newURL: URL) {
        let oldKey = oldURL.normalizedPathKey
        let newKey = newURL.normalizedPathKey
        guard oldKey != newKey else { return }
        guard let value = values.removeValue(forKey: oldKey) else { return }
        values[newKey] = value
    }
}
