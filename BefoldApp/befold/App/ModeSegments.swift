import AppKit

/// モード切替セグメントに並べる表示モードと、その順序。
///
/// セグメントの添字はこの配列の添字で解決し、`ViewerDisplayMode` の値そのものからは導かない。
/// 差分セグメントはフィーチャーゲートが無効なビルドでは**存在しない**ため、
/// モードと添字の対応が固定ではないからである(添字を列挙の rawValue に直結させると、
/// stable ビルドでソースを選んだつもりで差分が選ばれるような静かな取り違えになる)。
@MainActor
enum ModeSegments {
    static let all: [ViewerDisplayMode] = modes(isSourceDiffEnabled: FeatureGate.isSourceDiffEnabled)

    /// テスト可能な純粋判定。実ビルドではゲートが片側に固定されるため、両分岐はここで検証する
    /// （ゲート越しの検証は動いているビルドの側しか通らない）。
    static func modes(isSourceDiffEnabled: Bool) -> [ViewerDisplayMode] {
        isSourceDiffEnabled ? [.rendered, .source, .diff] : [.rendered, .source]
    }

    /// セグメントの表示に使う SF Symbol 名。
    ///
    /// 差分セグメントだけは固定ではなく、**現在の差分レイアウトの絵**を出す。
    /// インラインは 1 カラムに +/- 行が混ざる見た目、左右分割は 2 面の分割そのもので、
    /// どちらのアイコンもそのレイアウトを写している。これによりセグメントが
    /// 「いまどちらのレイアウトか」の表示を兼ね、独立したレイアウトボタンが要らなくなる。
    /// レイアウトを引数で受けるのは、両方の状態をユニットテストで押さえるため
    /// (`modes(isSourceDiffEnabled:)` と同じ理由)。
    static func symbol(for mode: ViewerDisplayMode, isSideBySide: Bool) -> String {
        switch mode {
        case .rendered: "doc.richtext"
        case .source: "chevron.left.forwardslash.chevron.right"
        case .diff: isSideBySide ? "rectangle.split.2x1" : "plus.forwardslash.minus"
        }
    }

    /// 差分セグメントのクリックが「モード選択」と「レイアウト切替」のどちらになるか。
    enum SegmentAction: Equatable {
        case select(ViewerDisplayMode)
        case toggleDiffLayout
    }

    /// クリックされたセグメントと、押す前の表示モードから動作を決める。
    ///
    /// 差分表示中に差分セグメントを押し直したときだけレイアウト切替になる。判定を
    /// 純粋関数にしているのは、AppKit のイベントを起こさずに両方の分岐を
    /// テストで押さえるため（`modes(isSourceDiffEnabled:)` と同じ理由）。
    static func action(for tapped: ViewerDisplayMode, current: ViewerDisplayMode) -> SegmentAction {
        tapped == .diff && current == .diff ? .toggleDiffLayout : .select(tapped)
    }

    static func labelKey(for mode: ViewerDisplayMode) -> String.LocalizationValue {
        switch mode {
        case .rendered: "toolbar.mode.preview"
        case .source: "toolbar.mode.source"
        case .diff: "toolbar.mode.diff"
        }
    }
}
