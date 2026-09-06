import AppKit

/// スライド窓のキー操作が起こす動作(TASK-593.3)。
///
/// キーと動作の対応を**純粋関数へ切り出す**のが要点で、`SidebarKeyAction` と同じ流儀。
/// GUI 層は自動テスト対象外なので、「修飾キー付きが素通しされる」「検索欄に入力中は
/// 素通しされる」を測れるのはこの関数のユニットテストだけになる。
///
/// **`characters` ではなく `keyCode` で判定する。** 矢印キーの `characters` は
/// 非印字文字（`NSUpArrowFunctionKey` 等）で、キーボードレイアウトによっても変わる。
/// keyCode は物理キーの位置なのでレイアウトに依らない。
enum SlideKeyAction: Equatable {
    /// 次のファイルへ移る。
    case next
    /// 前のファイルへ移る。
    case previous
    /// 何もしない（イベントを消費せず素通しする）。
    case ignored

    /// 物理キーの keyCode。US 配列に限らない値なので名前を付けて 1 箇所に置く。
    enum KeyCode {
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }

    /// - Parameters:
    ///   - keyCode: 押された物理キー。
    ///   - modifiers: 修飾キーの押下状態。
    ///   - isEditingText: first responder がテキスト入力中か。検索欄で Space や
    ///     Backspace を打っているときにファイルが送られてはならない。
    static func action(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isEditingText: Bool
    ) -> SlideKeyAction {
        // 入力中はどのキーも本文へ渡す。**この判定を最初に置く。**後ろに置くと
        // 「Space だけ先に食う」ような順序依存の穴ができる。
        guard !isEditingText else { return .ignored }
        // ⌘ / ⌥ / ⌃ 付きはメニューのキー等価が勝つので触らない。shift だけは
        // Shift+Space を「前へ」に使うため通す。
        guard !modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control)
        else { return .ignored }

        switch keyCode {
        case KeyCode.space:
            return modifiers.contains(.shift) ? .previous : .next
        case KeyCode.downArrow:
            return .next
        case KeyCode.upArrow, KeyCode.delete:
            return .previous
        default:
            return .ignored
        }
    }

    /// この動作の行き先。端では nil(周回しない)。
    ///
    /// **`snapshot` を引数で受ける**のが要点。`FileListModel.listSnapshot` は読むたびに
    /// 再計算するので(TASK-418)、呼び出し側が 1 度読んだものを渡す形にしておけば、
    /// 1 回のキー操作で 2 度読む書き方ができない。
    ///
    /// フォルダー行を飛ばすことと端で止まることは `FileListSnapshot` 側が持つ。
    @MainActor
    func destination(
        in snapshot: FileListSnapshot, from selection: FileListEntry.ID?
    ) -> FileListEntry? {
        switch self {
        case .next: snapshot.nextFile(after: selection)
        case .previous: snapshot.previousFile(before: selection)
        case .ignored: nil
        }
    }
}
