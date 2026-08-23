/// 文書内ジャンプの目印の種類（TASK-485）。
///
/// `rawValue` は viewer 側の `JumpProvider.id` と一対一で対応する。
/// Swift 側はこの値を `ViewerBridge.openJumpScript(kind:)` へ渡すだけで、
/// 目印をどう列挙するかは viewer 側のプロバイダが持つ。
enum DocumentJumpKind: String, CaseIterable {
    /// Markdown レンダリング表示の h1 / h2 / h3 見出し。
    case heading

    /// 差分表示中の変更ブロック(連続する追加・削除行のまとまり)。
    case changeBlock

    /// ソースコード表示中の関数・型の定義行(TASK-485.4)。
    /// 対応言語は `FunctionJumpLanguages.supported` に限る。
    case functionDefinition

    /// Edit メニューの項目が「どの種類のジャンプか」を運ぶためのタグ。
    /// `NSMenuItem.tag` の既定値は 0 で「未設定」と区別できないため 1 から振る。
    /// 表示モード選択（`ViewerDisplayMode.menuItemTag`）とは別のアクションに
    /// 付くため、値域が重なっていても取り違えは起きない。
    var menuItemTag: Int {
        switch self {
        case .heading: 1
        case .changeBlock: 2
        case .functionDefinition: 3
        }
    }

    /// メニュー項目の項目名のローカライズキー。
    var menuLabelKey: String.LocalizationValue {
        switch self {
        case .heading: "menu.edit.jumpToHeading"
        case .changeBlock: "menu.edit.jumpToChangeBlock"
        case .functionDefinition: "menu.edit.jumpToFunctionDefinition"
        }
    }

    /// メニュー項目のタグから種類を復元する。該当が無ければ nil（他の項目のタグ）。
    init?(menuItemTag tag: Int) {
        guard let kind = Self.allCases.first(where: { $0.menuItemTag == tag }) else { return nil }
        self = kind
    }
}
