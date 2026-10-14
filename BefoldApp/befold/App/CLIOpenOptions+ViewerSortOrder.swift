import BefoldKit
import Foundation

/// CLI 層の `CLIOpenOptions` を Viewer 層の型へ変換する境界アダプタ。
///
/// CLI 側の並び順は「指定なし」を表現できる一方、Viewer 側の `SortOrder` は常に具体値を持つ。
/// その差を GUI の入口(AppDelegate / SessionRestorer)で都度書き分けずに済むよう、ここへ集約する。
extension CLIOpenOptions {
    /// Viewer へ渡す並び順。CLI が `--sort alphabetical` を指定した場合のみ辞書順、
    /// それ以外(未指定を含む)は既定のフォルダー優先。
    var viewerSortOrder: SortOrder {
        sortOrder == .alphabetical ? .alphabetical : .foldersFirst
    }

    /// Viewer へ渡す表示モード(未指定は nil)。降格(種別が持たないモード)は適用側が行う。
    var viewerDisplayMode: ViewerDisplayMode? {
        switch displayMode {
        case .rendered: .rendered
        case .source: .source
        case .diff: .diff
        case nil: nil
        }
    }

    /// 開き方。`--new-window` は既存の窓を再利用しない(`ViewerWindowOpenPolicy.reusableController`)。
    var openDisposition: OpenDisposition {
        opensInNewWindow ? .newWindow : .currentTab
    }

    /// Viewer へ渡す差分の比較基準(未指定は nil)。
    var viewerComparisonTarget: GitComparisonTarget? {
        switch comparisonTarget {
        case .parentBranch: .parentBranch
        case .defaultBranch: .defaultBranch
        case .head: .head
        case nil: nil
        }
    }
}
