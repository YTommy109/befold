import Foundation

/// サイドバーの開閉状態をファイル(ウィンドウ)毎に UserDefaults へ永続化し、再起動後の復元と
/// 新規ウィンドウのデフォルト値解決に使う。パスはシンボリックリンク解決後の絶対パスで正規化して保持する。
@MainActor
final class SidebarStateStore {
    private static let lastToggledKey = "SidebarLastToggledCollapsed"

    private let defaults: UserDefaults
    private let collapsedStates: PathKeyedDictionary<Bool>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collapsedStates = PathKeyedDictionary(defaults: defaults, key: "SidebarCollapsedStates")
    }

    /// 指定ファイルの保存済み開閉状態を返す。保存がなければ nil。
    func isCollapsed(for url: URL) -> Bool? {
        collapsedStates.value(for: url)
    }

    /// 指定ファイルの開閉状態を保存する。ウィンドウを開いた時点の解決結果を記録する用途で使い、
    /// 「ユーザーが最後に操作した開閉状態」(lastToggledCollapsed)は書き換えない。
    func setCollapsed(_ collapsed: Bool, for url: URL) {
        collapsedStates.setValue(collapsed, for: url)
    }

    /// ユーザーがサイドバーを明示的に開閉操作したときに呼ぶ。ファイル単位の記録に加え、
    /// 「ユーザーが最後に操作した開閉状態」としても記録する。
    func recordToggle(_ collapsed: Bool, for url: URL) {
        setCollapsed(collapsed, for: url)
        defaults.set(collapsed, forKey: Self.lastToggledKey)
    }

    /// ユーザーが最後に操作した開閉状態。未操作なら既定(閉じた状態 = true)。
    var lastToggledCollapsed: Bool {
        guard defaults.object(forKey: Self.lastToggledKey) != nil else { return true }
        return defaults.bool(forKey: Self.lastToggledKey)
    }

    /// 新規ウィンドウの初期開閉状態を、
    /// (1) このファイル自身の保存値 → (2) 直近アクティブだったウィンドウ(ファイル)の保存値 →
    /// (3) ユーザーが最後に操作した開閉状態、の優先順で解決する。
    func initialCollapsed(for url: URL, lastActivePathKey: String?) -> Bool {
        if let saved = isCollapsed(for: url) { return saved }
        if let lastActivePathKey,
           let activeCollapsed = isCollapsed(for: URL(fileURLWithPath: lastActivePathKey))
        {
            return activeCollapsed
        }
        return lastToggledCollapsed
    }

    /// ファイルの rename / move に伴い、旧パスの開閉状態を新パスへ引き継ぐ。
    func migrateCollapsed(from oldURL: URL, to newURL: URL) {
        collapsedStates.migrateValue(from: oldURL, to: newURL)
    }
}
