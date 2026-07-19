import Foundation

/// ウィンドウのフレーム(位置＋サイズ)をファイル(ウィンドウ)毎に UserDefaults へ永続化し、
/// 再起動後の復元と新規ウィンドウのデフォルト値解決に使う。SidebarStateStore と同型の設計。
/// フレームは NSWindow.frameDescriptor 形式の文字列として保持する。
@MainActor
final class WindowFrameStore {
    private static let lastUserAdjustedKey = "WindowFrameLastUserAdjusted"

    private let defaults: UserDefaults
    private let frames: PathKeyedDictionary<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        frames = PathKeyedDictionary(defaults: defaults, key: "WindowFrames")
    }

    /// 指定ファイルの保存済みフレーム記述子を返す。保存がなければ nil。
    func frameDescriptor(for url: URL) -> String? {
        frames.value(for: url)
    }

    /// 指定ファイルのフレーム記述子を保存する。ウィンドウを開いた時点の解決結果を記録する用途で使い、
    /// 「ユーザーが最後に調整したフレーム」(lastUserAdjustedFrameDescriptor)は書き換えない。
    func setFrameDescriptor(_ descriptor: String, for url: URL) {
        frames.setValue(descriptor, for: url)
    }

    /// ユーザーがウィンドウをリサイズ/移動したときに呼ぶ。ファイル単位の記録に加え、
    /// 「ユーザーが最後に調整したフレーム」としても記録する。
    func recordUserAdjustedFrame(_ descriptor: String, for url: URL) {
        setFrameDescriptor(descriptor, for: url)
        defaults.set(descriptor, forKey: Self.lastUserAdjustedKey)
    }

    /// ユーザーが最後に調整したフレーム記述子。未調整なら nil。
    var lastUserAdjustedFrameDescriptor: String? {
        defaults.string(forKey: Self.lastUserAdjustedKey)
    }

    /// 新規ウィンドウの初期フレームを、
    /// (1) このファイル自身の保存値 → (2) 直近アクティブだったウィンドウ(ファイル)の保存値 →
    /// (3) ユーザーが最後に調整したフレーム、の優先順で解決する。すべて記録がなければ nil を返し、
    /// 呼び出し側で既定のカスケード配置にフォールバックする。
    func initialFrameDescriptor(for url: URL, lastActivePathKey: String?) -> String? {
        if let saved = frameDescriptor(for: url) { return saved }
        if let lastActivePathKey,
           let activeFrame = frameDescriptor(for: URL(fileURLWithPath: lastActivePathKey))
        {
            return activeFrame
        }
        return lastUserAdjustedFrameDescriptor
    }

    /// ファイルの rename / move に伴い、旧パスのフレーム記述子を新パスへ引き継ぐ。
    func migrateFrameDescriptor(from oldURL: URL, to newURL: URL) {
        frames.migrateValue(from: oldURL, to: newURL)
    }
}
