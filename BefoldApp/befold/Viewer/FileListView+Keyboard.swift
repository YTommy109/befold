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
    ///
    /// **絞り込み結果のスナップショットはここで 1 回だけ採り、以降は引数で渡す。**
    /// 選択中の行の判定・移動先の決定・親行の探索が同じ一覧を要るため、都度
    /// `model.visibleEntries` を読むと 1 打鍵で `FileListFilter.apply` が何度も
    /// 走る(TASK-418)。
    func handleKey(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> KeyPress.Result {
        let snapshot = model.listSnapshot
        // キーと動作の対応は表示モードを引数で受ける純粋関数(SidebarKeyAction)に置き、
        // ここは返った動作を 1 回 switch するだけにする。分岐を各アクションへ散らすと、
        // ドリルダウン側の割り当てが変わっていないことを測る場所が無くなる。
        return perform(
            SidebarKeyAction.action(
                key: key, modifiers: modifiers,
                target: snapshot.entry(for: model.selection).map(SidebarKeyAction.Target.init(entry:)),
                mode: model.layoutMode
            ),
            in: snapshot
        )
    }

    private func perform(_ action: SidebarKeyAction, in snapshot: FileListSnapshot) -> KeyPress.Result {
        switch action {
        case .selectNext: selectNext(in: snapshot)
        case .selectPrevious: selectPrevious(in: snapshot)
        case .navigateToParent: navigateToParent(in: snapshot)
        // `perform` の switch は default を持つため、新しいケースを足しても
        // コンパイラは漏れを教えない。選択行を要しない動作はここへ明示的に書く。
        case .selectParent: selectParentRow()
        case .ignored: .ignored
        // 残りはいずれも選択行を必要とする。選択が無ければ何もしない、という
        // 同じ前提を 1 箇所にまとめる。
        default: performOnSelectedEntry(action, in: snapshot)
        }
    }

    private func performOnSelectedEntry(
        _ action: SidebarKeyAction, in snapshot: FileListSnapshot
    ) -> KeyPress.Result {
        guard let entry = snapshot.entry(for: model.selection) else { return .ignored }
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
    ///
    /// 選択が絞り込みで隠れている場合は、選択が無い場合と同じく絞り込み結果の
    /// 先頭へ移す(行き先の決め方は `FileListSnapshot` を参照)。
    func selectNext(in snapshot: FileListSnapshot) -> KeyPress.Result {
        move(to: snapshot.next(after: model.selection))
    }

    /// 選択を前のエントリへ戻す。テストから直接呼べるよう internal。
    /// 選択が隠れている場合は絞り込み結果の末尾へ移す。
    func selectPrevious(in snapshot: FileListSnapshot) -> KeyPress.Result {
        move(to: snapshot.previous(before: model.selection))
    }

    /// 移動先が決まっていれば選択を移し、ファイルなら開く。
    private func move(to entry: FileListEntry?) -> KeyPress.Result {
        guard let entry else { return .ignored }
        model.selection = entry.id
        openIfFile(entry)
        return .handled
    }

    /// ツリー内で 1 つ上の階層の行へ選択を移す。**ルートは変えない。**
    ///
    /// 行き先は必ずフォルダ行なので `openIfFile` は呼ばない(呼んでも何も起きない)。
    /// 画面のスクロール追従は `FileListModel.selection` の didSet が行うため、
    /// ここで足す必要はない。最上位の行では親が無く `.ignored` になる。
    private func selectParentRow() -> KeyPress.Result {
        guard let current = model.selection, let parent = model.parentRow(of: current) else {
            return .ignored
        }
        model.selection = parent.id
        return .handled
    }

    private func navigateToParent(in snapshot: FileListSnapshot) -> KeyPress.Result {
        if let parent = snapshot.parentNavigationEntry {
            onNavigate(parent.url)
            return .handled
        }
        return .ignored
    }
}
