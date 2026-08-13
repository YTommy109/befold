import AppKit
import BefoldKit
import SwiftUI

/// サイドバー一覧の行の右クリックメニュー。
///
/// `FileListView` から分けているのは、ここが扱うのが「行に対する副次的な操作」で
/// あって一覧そのものの表示ではないため(`SidebarHeaderView` と同じ切り分け)。
/// 「別の場所で開く」の配線もここへ寄せ、`FileListView` 側は開き先を知らない。
struct SidebarContextMenu: View {
    let entry: FileListEntry
    /// コピーする相対パスの基準(git ルート / ワークスペースルート)を持つ。
    let model: FileListModel
    /// 行操作の受け手。ウィンドウ側が保持するため弱参照で持つ。
    weak var delegate: FileListViewDelegate?

    var body: some View {
        if entry.kind != .parentNavigation {
            Button(String(localized: "sidebar.context.copy", bundle: .l10n)) {
                Pasteboard.writeFileReference(entry.url)
            }
            openElsewhereButtons
            Button(String(localized: "sidebar.context.copyPath", bundle: .l10n)) {
                Pasteboard.writeString(model.relativePathForCopy(entry.url))
            }
            Button(String(localized: "sidebar.context.revealInFinder", bundle: .l10n)) {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
    }

    /// 「別の場所で開く」系の項目定義(並び・文言キー・開き先)。項目を数える単一情報源を
    /// ここに置き、片方の開き先だけメニューから抜け落ちるのを防ぐ。
    static let openElsewhereEntries: [(titleKey: String, disposition: OpenDisposition)] = [
        ("sidebar.context.openInNewTab", .newTab),
        ("sidebar.context.openInNewWindow", .newWindow),
    ]

    private var openElsewhereButtons: some View {
        ForEach(Self.openElsewhereEntries, id: \.titleKey) { item in
            openElsewhereButton(titleKey: item.titleKey, disposition: item.disposition)
        }
    }

    /// フォルダー行では「そのフォルダーで最初に開けるファイル」を開き先にする。
    /// 走査はメインを止めないよう detached で行い、開けるファイルが無い行は無効化する。
    @ViewBuilder
    private func openElsewhereButton(titleKey: String, disposition: OpenDisposition) -> some View {
        let label = String(localized: String.LocalizationValue(titleKey), bundle: .l10n)
        if entry.kind == .folder {
            let folder = entry.url
            Button(label) {
                Task {
                    let detached = Task.detached { DirectoryLister.firstSupportedFile(in: folder) }
                    if let first = await detached.value {
                        delegate?.fileListDidRequestOpenElsewhere(first, disposition: disposition)
                    }
                }
            }
            .disabled(!entry.containsSupportedFile)
        } else {
            Button(label) {
                delegate?.fileListDidRequestOpenElsewhere(entry.url, disposition: disposition)
            }
        }
    }
}
