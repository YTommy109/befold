import Foundation

/// ディスクに触れない UserDefaults。
///
/// 以前は UserDefaults(suiteName: "<接頭辞>-<UUID>") で独立領域を作っていたが、
/// これは永続ドメインを作るため ~/Library/Preferences に plist が残り続け、
/// テスト 1 回につき百数十個が積み上がって cfprefsd を劣化させていた。
///
/// プロセス終了時に削除する方式は成立しない: 実測したところ、削除しても
/// cfprefsd が終了後 2 秒ほどで全ファイルを書き戻す(atexit ハンドラ内での
/// removePersistentDomain + ファイル削除は t=0 で 50/50 消えるが、t=+2s には
/// 50/50 復活する)。ディスク上のドメインを使う限りこの競合からは逃れられない。
///
/// そのため永続ドメインを作ること自体をやめ、メモリ上の辞書に閉じる。
/// 後始末が不要になり、テスト間の独立性もインスタンス単位で保証される。
///
/// Apple の規約どおりプリミティブメソッドを上書きする。string(forKey:) などの
/// 便利メソッドはこれらに委譲されるが、書き込み側は取りこぼすと利用者の実際の
/// 設定を汚しうるため、型付きセッターも明示的に塞いでいる。
private final class InMemoryUserDefaults: UserDefaults {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    // MARK: - プリミティブ

    override func object(forKey defaultName: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: defaultName)
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    override func synchronize() -> Bool {
        true
    }

    // MARK: - 型付きセッター

    // 実装が setObject:forKey: を経由する保証はないため、
    // 実際の設定ドメインへ書き込まれないよう個別に塞ぐ。

    override func set(_ value: Bool, forKey defaultName: String) {
        set(value as Any?, forKey: defaultName)
    }

    override func set(_ value: Int, forKey defaultName: String) {
        set(value as Any?, forKey: defaultName)
    }

    override func set(_ value: Double, forKey defaultName: String) {
        set(value as Any?, forKey: defaultName)
    }

    override func set(_ value: Float, forKey defaultName: String) {
        set(value as Any?, forKey: defaultName)
    }

    override func set(_ url: URL?, forKey defaultName: String) {
        set(url as Any?, forKey: defaultName)
    }
}

/// テストごとに独立した UserDefaults を用意する。
/// 本番の共有スイート("com.degino.befold")への書き込みを避けるため、
/// UserDefaults を伴う挙動を検証するテストはこちらを介した独立領域を使う。
///
/// 返るのはメモリ上の実装(InMemoryUserDefaults)で、ディスクには何も作らない。
/// 呼び出し側での後始末は不要。prefix は呼び出し箇所を読みやすくするためだけに
/// 残しており、格納先には影響しない。
///
/// 過去に堆積した plist の掃除は scripts/clean-test-defaults.sh が担う。
public func makeIsolatedDefaults(prefix _: String) -> UserDefaults {
    InMemoryUserDefaults()
}
