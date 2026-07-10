import Foundation

/// 検索バーの3トグル(大文字小文字区別・単語マッチ・正規表現)を UserDefaults に永続化する。
/// ファイル単位ではなくアプリ全体で共有する単一の状態(ZoomStore の per-file 方式とは異なる)。
@MainActor
final class FindOptionsPreference {
    private let defaults: UserDefaults
    private static let caseSensitiveKey = "FindCaseSensitive"
    private static let wholeWordKey = "FindWholeWord"
    private static let useRegexKey = "FindUseRegex"

    var caseSensitive: Bool {
        didSet { defaults.set(caseSensitive, forKey: Self.caseSensitiveKey) }
    }

    var wholeWord: Bool {
        didSet { defaults.set(wholeWord, forKey: Self.wholeWordKey) }
    }

    var useRegex: Bool {
        didSet { defaults.set(useRegex, forKey: Self.useRegexKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        caseSensitive = defaults.bool(forKey: Self.caseSensitiveKey)
        wholeWord = defaults.bool(forKey: Self.wholeWordKey)
        useRegex = defaults.bool(forKey: Self.useRegexKey)
    }
}
