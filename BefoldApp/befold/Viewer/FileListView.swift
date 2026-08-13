import AppKit
import BefoldKit
import SwiftUI

struct FileListView: View {
    @Bindable var model: FileListModel
    /// 行操作(選択・移動・別の場所で開く・展開/畳み)の受け手。
    /// ウィンドウ側(ViewerWindowController)が保持するため弱参照で持つ。
    weak var delegate: FileListViewDelegate?
    let onSortOrderChanged: (SortOrder) -> Void
    var onToggleHiddenFiles: (() -> Void)?
    /// nil のときはヘッダーに git 変更のみ表示のボタンを出さない。
    /// 開発中機能の露出点(ViewerWindowController が FeatureGate で決める)。
    var onToggleChangedFilesOnly: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeaderView(
                model: model,
                onSortOrderChanged: onSortOrderChanged,
                onToggleHiddenFiles: onToggleHiddenFiles,
                onToggleChangedFilesOnly: onToggleChangedFilesOnly
            )
            entryList
        }
    }

    /// 一覧が空のときの案内。文言の出し分けはプレビュー内フォルダー一覧
    /// (FolderListingView)と共有する(SidebarEmptyState)。片側にだけ理由の
    /// 出し分けを書くと、もう片方が「対応ファイルがありません」固定のまま残る。
    private var emptyStateView: some View {
        SidebarEmptyState(context: SidebarEmptyContext(model: model))
    }

    /// 一覧本体。**絞り込み結果は 1 回だけ採って List と空表示の判定で共有する。**
    /// 別々に `model.visibleEntries` を読むと body 1 回につき絞り込みが 2 回走る
    /// (TASK-418)。
    private var entryList: some View {
        entryList(showing: model.listSnapshot.visible)
    }

    private func entryList(showing entries: [FileListEntry]) -> some View {
        List(entries, selection: $model.selection) { entry in
            // 行インセットをゼロにして同等のパディングを行コンテンツ側へ移し、
            // contentShape が行の全幅を覆うようにする。インセット部分をダブル
            // クリックしたとき選択だけされて移動しない取りこぼしを防ぐ。
            FileListEntryRow(
                entry: entry, gitStatus: { model.gitStatus?.fileStatus(at: entry.pathKey) },
                gitFolderStatus: { model.gitStatus?.folderStatus(at: entry.pathKey) }
            )
            .padding(.horizontal, SidebarRowIndent.rowHorizontalPadding)
            .padding(.vertical, 2)
            .listRowInsets(EdgeInsets())
            .contentShape(.rect)
            .background(SidebarTableViewLocator { tableView in
                model.tableFocuser.tableView = tableView
            })
            .contextMenu {
                SidebarContextMenu(entry: entry, model: model, delegate: delegate)
            }
            .simultaneousGesture(singleTapGesture(for: entry))
            .simultaneousGesture(doubleTapGesture(for: entry))
        }
        .overlay {
            if entries.allSatisfy({ $0.kind == .parentNavigation }) {
                emptyStateView
                    .allowsHitTesting(false)
            }
        }
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }

    // MARK: - Click

    /// 開閉三角のクリックが起こす動作。三角の上でなければ nil(＝行本体のクリック)。
    ///
    /// GUI 層は自動テスト対象外なので、「三角の無い行では左端をクリックしても開閉しない」
    /// はこの関数のユニットテストが唯一の測り方になる
    /// (`ModeSegments.modes(isSourceDiffEnabled:)` と同じ形)。
    ///
    /// **座標だけで決めない。** ドリルダウン表示とプレビュー内のフォルダー一覧
    /// (FolderListingView)には三角が無く、同じ位置は行本体の一部でしかない。
    func disclosureAction(for entry: FileListEntry, atX offsetX: CGFloat) -> SidebarKeyAction? {
        guard entry.disclosure != nil else { return nil }
        guard SidebarRowIndent.isWithinDisclosure(offsetX: offsetX, depth: entry.depth) else {
            return nil
        }
        return SidebarKeyAction.disclosureToggleAction(target: SidebarKeyAction.Target(entry: entry))
    }

    /// 行の動作(展開・畳み・フォルダーへの移動)を delegate へ配る。
    /// シングルクリックとダブルクリックが同じ表を通るようにするための 1 箇所。
    private func performRowAction(_ action: SidebarKeyAction, on entry: FileListEntry) {
        switch action {
        case .navigateInto: delegate?.fileListDidRequestNavigation(to: entry.url)
        case .expand: delegate?.fileListDidRequestExpand(entry)
        // 展開済みのフォルダをもう一度指したら畳む(開閉のトグル)。
        case .collapse: delegate?.fileListDidRequestCollapse(entry)
        default: break
        }
    }

    /// シングルクリックで行を選択し、ファイルなら開く。
    /// List の選択バインディング任せにせず自前で選択を書くことで、
    /// プログラム的な選択更新とクリックが競合しても確実に反応させる。
    ///
    /// 開閉三角の上だけは選択を動かさず開閉だけを行う(Finder と同じ)。位置が要るため
    /// `TapGesture` ではなく `SpatialTapGesture` を使う。**判定を子ビュー側の
    /// ジェスチャに分けない**——行の修飾は `simultaneousGesture` なので、子が取っても
    /// 行のタップが同時に発火して選択まで走る。
    private func singleTapGesture(
        for entry: FileListEntry
    ) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local).onEnded { value in
            if let action = disclosureAction(for: entry, atX: value.location.x) {
                // 開閉は entries を差し替えるので、List がクリックの処理を終える前に
                // 触らないよう次のランループへ回す(固定待ちは不要)。
                DispatchQueue.main.async {
                    performRowAction(action, on: entry)
                }
                return
            }
            model.selection = entry.id
            openIfFile(entry)
            // List が選択を NSTableView へ反映し終える前に first responder を
            // 奪うと選択行とハイライトがズレるため、次のランループへ遅延する
            // (固定待ちは不要)。
            DispatchQueue.main.async {
                model.tableFocuser.focus()
            }
        }
    }

    /// 選択が確定したエントリがファイルなら表示を更新する。
    /// クリック・矢印キー・j/k など、選択を変えるすべての経路から呼ぶことで
    /// 「選択は動くが表示が追従しない」状態を防ぐ。
    func openIfFile(_ entry: FileListEntry) {
        if entry.kind == .file {
            delegate?.fileListDidSelectFile(entry.url)
        }
    }

    private func doubleTapGesture(
        for entry: FileListEntry
    ) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local).onEnded { value in
            // 三角の上では何もしない。シングルタップ側が既に 2 回開閉しており、
            // ここでも動くと 1 回のダブルクリックで 3 回トグルされる。
            guard disclosureAction(for: entry, atX: value.location.x) == nil else { return }
            // return キーと同じ判断源を通す。別々に分岐を書くと、片方だけツリー対応して
            // 「ダブルクリックでは展開できない」という穴が残る(TASK-320 と同型)。
            let action = SidebarKeyAction.doubleClickAction(
                target: SidebarKeyAction.Target(entry: entry), mode: model.layoutMode
            )
            // List が 2 クリック目のイベント処理を終える前に entries を
            // 差し替えないよう、次のランループまで遅延する(固定待ちは不要)。
            DispatchQueue.main.async {
                performRowAction(action, on: entry)
            }
        }
    }
}
