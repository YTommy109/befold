import AppKit
import SwiftUI

/// サイドバーのキーボード操作。FileListView 本体から分けているのは、swiftlint の
/// file_length / type_body_length / cyclomatic_complexity を超えないようにするため。
///
/// キーと動作の対応そのものは `SidebarKeyAction`(表示モードを引数で受ける純粋関数)にあり、
/// ここはその動作を実際の副作用へ結び付けるだけ。
extension FileListView {
    // MARK: - Keyboard Navigation

    /// サイドバーがアクティブなときのキー操作を処理する。
    func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        handleKey(keyPress.key, modifiers: keyPress.modifiers)
    }

    /// キーとアクションの対応付け。`KeyPress` は公開イニシャライザがなくテストで
    /// 直接構築できないため、`KeyEquivalent` と修飾キーだけを受け取るこの関数を
    /// internal にしてテストから直接呼べるようにしている。
    func handleKey(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> KeyPress.Result {
        // キーと動作の対応は表示モードを引数で受ける純粋関数(SidebarKeyAction)に置き、
        // ここは返った動作を 1 回 switch するだけにする。分岐を各アクションへ散らすと、
        // ドリルダウン側の割り当てが変わっていないことを測る場所が無くなる。
        perform(
            SidebarKeyAction.action(
                key: key, modifiers: modifiers, target: selectedTarget, mode: model.layoutMode
            )
        )
    }

    /// 選択中の行を、動作の判断に要る形にしたもの。選択が無ければ nil。
    private var selectedTarget: SidebarKeyAction.Target? {
        selectedEntry.map(SidebarKeyAction.Target.init(entry:))
    }

    private var selectedEntry: FileListEntry? {
        guard let current = model.selection else { return nil }
        return model.visibleEntries.first { $0.id == current }
    }

    private func perform(_ action: SidebarKeyAction) -> KeyPress.Result {
        switch action {
        case .selectNext: selectNext()
        case .selectPrevious: selectPrevious()
        case .navigateToParent: navigateToParent()
        case .ignored: .ignored
        // 残りはいずれも選択行を必要とする。選択が無ければ何もしない、という
        // 同じ前提を 1 箇所にまとめる。
        default: performOnSelectedEntry(action)
        }
    }

    private func performOnSelectedEntry(_ action: SidebarKeyAction) -> KeyPress.Result {
        guard let entry = selectedEntry else { return .ignored }
        switch action {
        case .navigateInto: onNavigate(entry.url)
        case .openFile: openIfFile(entry)
        case .expand: onExpandFolder?(entry)
        case .collapse: onCollapseFolder?(entry)
        default: return .ignored
        }
        return .handled
    }

    /// 選択を次のエントリへ進める。テストから直接呼べるよう internal。
    func selectNext() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.visibleEntries.firstIndex(where: { $0.id == current }),
              index + 1 < model.visibleEntries.count
        else {
            if model.selection == nil, let first = model.visibleEntries.first {
                model.selection = first.id
                openIfFile(first)
                return .handled
            }
            return .ignored
        }
        let next = model.visibleEntries[index + 1]
        model.selection = next.id
        openIfFile(next)
        return .handled
    }

    /// 選択を前のエントリへ戻す。テストから直接呼べるよう internal。
    func selectPrevious() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.visibleEntries.firstIndex(where: { $0.id == current }),
              index > 0
        else {
            return .ignored
        }
        let previous = model.visibleEntries[index - 1]
        model.selection = previous.id
        openIfFile(previous)
        return .handled
    }

    private func enterSelected() -> KeyPress.Result {
        guard let current = model.selection,
              let entry = model.visibleEntries.first(where: { $0.id == current })
        else {
            return .ignored
        }
        switch entry.kind {
        case .parentNavigation, .folder:
            onNavigate(entry.url)
            return .handled
        case .file:
            openIfFile(entry)
            return .handled
        }
    }

    private func navigateToParent() -> KeyPress.Result {
        if let parent = model.visibleEntries.first(where: { $0.kind == .parentNavigation }) {
            onNavigate(parent.url)
            return .handled
        }
        return .ignored
    }
}
