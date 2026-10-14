import BefoldKit

/// CLI が指定した「この起動限りの」表示の上書き。窓の生成(`ViewerWindowController.init`)と
/// 既存窓への適用(`ViewerDisplayOptionsApplier`)が同じ値を受け取るための束ね。
/// 3 つを別々の引数で運ぶと、増えるたびに両方の経路の引数列を直すことになる。
struct CLIDisplayOverrides: Equatable {
    var mode: ViewerDisplayMode?
    var comparisonTarget: GitComparisonTarget?
    /// 開いた直後に表示する行(1 始まり)。
    var line: Int?

    static let none = CLIDisplayOverrides()

    /// いずれの指定も無いか。
    var isEmpty: Bool {
        self == .none
    }
}

extension CLIDisplayOverrides {
    init(_ options: CLIOpenOptions) {
        self.init(
            mode: options.viewerDisplayMode, comparisonTarget: options.viewerComparisonTarget,
            line: options.line
        )
    }
}
