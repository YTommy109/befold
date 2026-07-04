import Foundation

/// UserDefaults 上の「正規化パス → 値」辞書を読み書きする共通基盤。
/// キーの正規化(normalizedPathKey)と rename 時のキー付け替えの規約をここに集約する。
struct PathKeyedDictionary<Value> {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    /// 指定ファイルの保存値を返す。保存がなければ nil。
    func value(for url: URL) -> Value? {
        values()[url.normalizedPathKey]
    }

    /// 指定ファイルの値を保存する。
    func setValue(_ value: Value, for url: URL) {
        var dict = values()
        dict[url.normalizedPathKey] = value
        defaults.set(dict, forKey: key)
    }

    /// ファイルの rename / move に伴い、旧パスの値を新パスへ引き継ぐ。
    /// 旧パスに保存値がなければ何もしない。移行後は旧キーを削除する。
    func migrateValue(from oldURL: URL, to newURL: URL) {
        let oldKey = oldURL.normalizedPathKey
        let newKey = newURL.normalizedPathKey
        guard oldKey != newKey else { return }
        var dict = values()
        guard let value = dict.removeValue(forKey: oldKey) else { return }
        dict[newKey] = value
        defaults.set(dict, forKey: key)
    }

    private func values() -> [String: Value] {
        defaults.dictionary(forKey: key) as? [String: Value] ?? [:]
    }
}
