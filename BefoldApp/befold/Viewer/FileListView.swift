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
            .padding(.horizontal, 8)
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

    /// シングルクリックで行を選択し、ファイルなら開く。
    /// List の選択バインディング任せにせず自前で選択を書くことで、
    /// プログラム的な選択更新とクリックが競合しても確実に反応させる。
    private func singleTapGesture(
        for entry: FileListEntry
    ) -> some Gesture {
        TapGesture().onEnded {
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
        TapGesture(count: 2).onEnded {
            // return キーと同じ判断源を通す。別々に分岐を書くと、片方だけツリー対応して
            // 「ダブルクリックでは展開できない」という穴が残る(TASK-320 と同型)。
            let action = SidebarKeyAction.doubleClickAction(
                target: SidebarKeyAction.Target(entry: entry), mode: model.layoutMode
            )
            // List が 2 クリック目のイベント処理を終える前に entries を
            // 差し替えないよう、次のランループまで遅延する(固定待ちは不要)。
            DispatchQueue.main.async {
                switch action {
                case .navigateInto:
                    delegate?.fileListDidRequestNavigation(to: entry.url)
                case .expand:
                    delegate?.fileListDidRequestExpand(entry)
                // 展開済みのフォルダをダブルクリックしたら畳む(開閉のトグル)。
                case .collapse:
                    delegate?.fileListDidRequestCollapse(entry)
                default:
                    break
                }
            }
        }
    }
}
