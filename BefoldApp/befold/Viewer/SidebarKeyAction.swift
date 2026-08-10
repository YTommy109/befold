import SwiftUI

/// サイドバーのキー操作・ダブルクリックが起こす動作。
///
/// キーと動作の対応を **表示モードを引数で受ける純粋関数** に切り出すのが要点。
/// GUI 層は自動テスト対象外なので、「ツリー表示を足してもドリルダウンの割り当てが
/// 変わっていない」ことはこの関数のユニットテストが唯一の測り方になる
/// (`ModeSegments.modes(isSourceDiffEnabled:)` と同じ形)。
///
/// キー操作(`return` / `→`)とダブルクリックの両方がここを通る。別々に分岐を書くと、
/// 片方だけツリー対応して予告どおりの穴が残る(TASK-320 と同型)。
enum SidebarKeyAction: Equatable {
    /// 選択を次の行へ。
    case selectNext
    /// 選択を前の行へ。
    case selectPrevious
    /// 選択中のフォルダへ入る(ルートを変える)。
    case navigateInto
    /// 上位フォルダーへ移動する(ルートを変える)。
    case navigateToParent
    /// ツリー内で 1 つ上の階層の行へ選択を移す(ルートは変えない)。
    case selectParent
    /// 選択中のファイルを開く。
    case openFile
    /// 選択中のフォルダを展開する。
    case expand
    /// 選択中のフォルダを畳む。
    case collapse
    /// 何もしない。
    case ignored

    /// 選択されている行の、動作を決めるのに要る性質。
    struct Target: Equatable {
        var kind: FileListEntry.Kind
        /// ツリー表示で、そのフォルダが展開されているか(`.folder` のときのみ意味を持つ)。
        var isExpanded: Bool = false

        init(kind: FileListEntry.Kind, isExpanded: Bool = false) {
            self.kind = kind
            self.isExpanded = isExpanded
        }

        init(entry: FileListEntry) {
            kind = entry.kind
            // 列挙に失敗した行も「展開されている」側に置く。畳む操作(←)を届かせるため
            // であり、逆に展開(→)を出すと `beginExpanding` が弾いて無反応になる。
            isExpanded = switch entry.disclosure {
            case .expanded, .expandedEmpty, .loadingChildren, .expandedFailed: true
            case .collapsed, nil: false
            }
        }
    }

    /// - Parameters:
    ///   - target: 選択中の行。選択が無ければ nil。
    ///   - mode: 表示モード。`.drillDown` の割り当ては従来から一切変えない。
    static func action(
        key: KeyEquivalent, modifiers: EventModifiers, target: Target?, mode: SidebarLayoutMode
    ) -> SidebarKeyAction {
        switch key {
        case "j", .downArrow:
            .selectNext
        // Finder 準拠の「上のフォルダーへ移動」。修飾キーなしの ↑ / k(選択移動)と
        // 衝突させないため、下の `.upArrow` より前に置く。
        case .upArrow where modifiers.contains(.command):
            .navigateToParent
        case "k", .upArrow:
            .selectPrevious
        case .return, .rightArrow, "l":
            forward(target: target, mode: mode)
        case .leftArrow, "h":
            backward(target: target, mode: mode)
        // delete はツリー表示でも「ルートを 1 つ上げる」のまま。ツリーでは ← が
        // 畳みになるため、上へ出る手段をここに残しておかないとキーボードだけで
        // ルートより上へ行けなくなる。
        case .delete:
            .navigateToParent
        default:
            .ignored
        }
    }

    /// ダブルクリックの動作。
    ///
    /// ツリー表示のフォルダ行だけは `return` と意図的に分かれる(開閉のトグルになる)。
    /// **`forward` の戻り値を読み替えて実現しない。** `.selectNext` を「畳む」の意味で
    /// 使い回すと、同じ値が呼び出し元によって別の動作になり、片方だけ直したときに
    /// 気付けない(TASK-408)。分かれるのはこの 1 ケースだけなので、ここで直に決める。
    static func doubleClickAction(target: Target, mode: SidebarLayoutMode) -> SidebarKeyAction {
        guard mode == .tree, target.kind == .folder else { return forward(target: target, mode: mode) }
        return target.isExpanded ? .collapse : .expand
    }

    private static func forward(target: Target?, mode: SidebarLayoutMode) -> SidebarKeyAction {
        guard let target else { return .ignored }
        switch target.kind {
        case .file:
            return .openFile
        case .parentNavigation:
            // `..` はツリー表示でも上位フォルダーへの移動手段のまま(展開はできない)。
            return .navigateInto
        case .folder:
            guard mode == .tree else { return .navigateInto }
            return target.isExpanded ? .selectNext : .expand
        }
    }

    /// ツリー表示の ← は **ルートを変えない**。→ が展開・選択移動というモード内の
    /// 動きしかしないのに ← だけツリーごと別の場所へ飛ぶと往復が非対称になるため、
    /// ルートの変更は cmd+↑ と delete に集約する(TASK-408)。Finder / Xcode /
    /// VS Code / NERDTree も「畳む、畳み済みか葉なら親フォルダの行へ」の二段構え。
    private static func backward(target: Target?, mode: SidebarLayoutMode) -> SidebarKeyAction {
        guard mode == .tree else { return .navigateToParent }
        guard let target, target.kind == .folder, target.isExpanded else {
            // 展開していない行・ファイル行では、ツリー内の親行へ選択を移す。
            // 最上位の行に親は無く、そこでは何も起きない(消費側で .ignored になる)。
            return .selectParent
        }
        return .collapse
    }
}
