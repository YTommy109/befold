import Foundation

/// テストごとに独立した UserDefaults スイートを用意する。
/// 本番の共有スイート("com.degino.befold")への書き込みを避けるため、
/// UserDefaults を伴う挙動を検証するテストはこちらを介した独立領域を使う。
public func makeIsolatedDefaults(prefix: String) -> UserDefaults {
    let suiteName = "\(prefix)-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
