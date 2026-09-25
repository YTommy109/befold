/// 文書内ジャンプの目印の種類（TASK-485）。
///
/// `rawValue` は viewer 側の `JumpProvider.id` と一対一で対応する。
/// Swift 側はこの値を `ViewerJumpBridge.toggleBarModeScript(mode:)` へ渡すだけで、
/// 目印をどう列挙するかは viewer 側のプロバイダが持つ。
enum DocumentJumpKind: String, CaseIterable {
    /// Markdown レンダリング表示の h1 / h2 / h3 見出し。
    case heading

    /// 差分表示中の変更ブロック(連続する追加・削除行のまとまり)。
    case changeBlock

    /// ソースコード表示中の関数・型の定義行(TASK-485.4)。
    /// 対応言語は `FunctionJumpLanguages.supported` に限る。
    case functionDefinition
}
