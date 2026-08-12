import AppKit
import BefoldKit
import SwiftUI

struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void
    let onNavigate: (URL) -> Void
    let onSortOrderChanged: (SortOrder) -> Void
    /// 選択行を別のタブ/ウィンドウで開く。disposition ごとにクロージャを分けず
    /// 1 本にまとめることで、開き先を増やしても配線が増えない
    /// (受け側の ViewerWindowController.openFileElsewhere も disposition を取る)。
    let onOpenElsewhere: (URL, OpenDisposition) -> Void
    /// ツリー表示でフォルダ行を展開する。既定は何もしない(ドリルダウン表示・テスト用)。
    /// 実際の列挙と行の組み直しは SidebarNavigator.expandFolder が行う。
    var onExpandFolder: ((FileListEntry) -> Void)?
    /// ツリー表示でフォルダ行を畳む。既定は何もしない。
    var onCollapseFolder: ((FileListEntry) -> Void)?
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
            .contextMenu { contextMenuItems(for: entry) }
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

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for entry: FileListEntry) -> some View {
        if entry.kind != .parentNavigation {
            Button(String(localized: "sidebar.context.copy", bundle: .l10n)) {
                copyFileReference(entry.url)
            }
            openElsewhereButtons(for: entry)
            Button(String(localized: "sidebar.context.copyPath", bundle: .l10n)) {
                copyPath(entry.url)
            }
            Button(String(localized: "sidebar.context.revealInFinder", bundle: .l10n)) {
                revealInFinder(entry.url)
            }
        }
    }

    /// 「別の場所で開く」系の項目定義(並び・文言キー・開き先)。項目を数える単一情報源を
    /// ここに置き、片方の開き先だけメニューから抜け落ちるのを防ぐ。
    static let openElsewhereEntries: [(titleKey: String, disposition: OpenDisposition)] = [
        ("sidebar.context.openInNewTab", .newTab),
        ("sidebar.context.openInNewWindow", .newWindow),
    ]

    private func openElsewhereButtons(for entry: FileListEntry) -> some View {
        ForEach(Self.openElsewhereEntries, id: \.titleKey) { item in
            openElsewhereButton(for: entry, titleKey: item.titleKey, disposition: item.disposition)
        }
    }

    /// フォルダー行では「そのフォルダーで最初に開けるファイル」を開き先にする。
    /// 走査はメインを止めないよう detached で行い、開けるファイルが無い行は無効化する。
    @ViewBuilder
    private func openElsewhereButton(
        for entry: FileListEntry, titleKey: String, disposition: OpenDisposition
    ) -> some View {
        let label = String(localized: String.LocalizationValue(titleKey), bundle: .l10n)
        if entry.kind == .folder {
            let folder = entry.url
            Button(label) {
                Task {
                    let detached = Task.detached { DirectoryLister.firstSupportedFile(in: folder) }
                    if let first = await detached.value {
                        onOpenElsewhere(first, disposition)
                    }
                }
            }
            .disabled(!entry.containsSupportedFile)
        } else {
            Button(label) {
                onOpenElsewhere(entry.url, disposition)
            }
        }
    }

    private func copyFileReference(_ url: URL) {
        Pasteboard.writeFileReference(url)
    }

    private func copyPath(_ url: URL) {
        Pasteboard.writeString(model.relativePathForCopy(url))
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
            onSelect(entry.url)
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
                    onNavigate(entry.url)
                case .expand:
                    onExpandFolder?(entry)
                // 展開済みのフォルダをダブルクリックしたら畳む(開閉のトグル)。
                case .collapse:
                    onCollapseFolder?(entry)
                default:
                    break
                }
            }
        }
    }
}
