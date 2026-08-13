import Foundation

/// サイドバーの一覧表示に関する ON/OFF を UserDefaults に永続化する。
/// ZoomStore と同じ「注入して共有する」パターンに倣い、全ウィンドウで
/// 同一インスタンスを共有することでアプリ全体・全ウィンドウ共通の状態にする。
@MainActor
final class SidebarDisplayPreference {
    private let defaults: UserDefaults
    private static let showHiddenFilesKey = "ShowHiddenFiles"
    private static let showChangedFilesOnlyKey = "ShowChangedFilesOnly"
    private static let layoutModeKey = "SidebarLayoutMode"
    private static let sortOrderKey = "SidebarSortOrder"

    /// 不可視ファイル(ドットファイル)を一覧に出すか。
    var showHiddenFiles: Bool {
        didSet {
            defaults.set(showHiddenFiles, forKey: Self.showHiddenFilesKey)
        }
    }

    /// git 変更のあるファイルだけに一覧を絞るか。
    /// 機能が無効なビルドでは切り替える手段(メニュー・ヘッダーボタン)が露出しないため、
    /// 保存値が ON でも起動時に OFF として読む。保存値そのものは書き換えないので、
    /// dev ビルドへ戻れば ON のまま復帰する(TASK-284)。
    var showChangedFilesOnly: Bool {
        didSet {
            defaults.set(showChangedFilesOnly, forKey: Self.showChangedFilesOnlyKey)
        }
    }

    /// サイドバーの行の並べ方(ドリルダウン / ツリー展開)。
    /// showChangedFilesOnly と同じく、機能が無効なビルドでは保存値がツリーでも
    /// ドリルダウンとして読む。保存値そのものは書き換えないので、dev ビルドへ戻れば
    /// ツリーのまま復帰する(TASK-284 と同じ形)。
    var layoutMode: SidebarLayoutMode {
        didSet {
            defaults.set(layoutMode.rawValue, forKey: Self.layoutModeKey)
        }
    }

    /// 一覧の並び順(フォルダー優先 / アルファベット順)。
    /// フィーチャーゲートの対象ではないため、保存値をそのまま読む。
    var sortOrder: SortOrder {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        }
    }

    /// - Parameters:
    ///   - isChangedFilesOnlyAvailable: 既定はフィーチャーゲートの判定。
    ///     テストから両方の状態を作れるようにするためだけの注入点で、本番では省略する。
    ///   - isTreeLayoutAvailable: 同上(サイドバーのツリー展開)。
    init(
        defaults: UserDefaults = .standard,
        isChangedFilesOnlyAvailable: Bool = FeatureGate.isSidebarGitStatusEnabled,
        isTreeLayoutAvailable: Bool = FeatureGate.isSidebarTreeEnabled
    ) {
        self.defaults = defaults
        showHiddenFiles = defaults.bool(forKey: Self.showHiddenFilesKey)
        showChangedFilesOnly = isChangedFilesOnlyAvailable
            && defaults.bool(forKey: Self.showChangedFilesOnlyKey)
        // init 内の代入では didSet が走らないため、降格して読んでも保存値は書き換わらない。
        let stored = SidebarLayoutMode.stored(defaults.string(forKey: Self.layoutModeKey))
        layoutMode = isTreeLayoutAvailable ? stored : .drillDown
        sortOrder = SortOrder.stored(defaults.string(forKey: Self.sortOrderKey))
    }
}
