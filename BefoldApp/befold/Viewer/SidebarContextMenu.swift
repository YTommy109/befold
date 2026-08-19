import AppKit
import BefoldKit
import SwiftUI

/// サイドバー一覧の行の右クリックメニュー。
///
/// `FileListView` から分けているのは、ここが扱うのが「行に対する副次的な操作」で
/// あって一覧そのものの表示ではないため(`SidebarHeaderView` と同じ切り分け)。
/// 「別の場所で開く」のメニュー項目定義と、フォルダ行の開き先解決はここへ寄せる。
/// 開き方と修飾キーの対応表そのものは `OpenDisposition` にあり、修飾キー付き
/// クリック / ⌘Return(`FileListView.handleRowTap` / `SidebarKeyAction`)も同じ表を通る。
struct SidebarContextMenu: View {
    let entry: FileListEntry
    /// コピーする相対パスの基準(git ルート / ワークスペースルート)を持つ。
    let model: FileListModel
    /// 行操作の受け手。ウィンドウ側が保持するため弱参照で持つ。
    weak var delegate: FileListViewDelegate?

    var body: some View {
        Group {
            Button(String(localized: "sidebar.context.copy", bundle: .l10n)) {
                Pasteboard.writeFileReference(entry.url)
            }
            openElsewhereButtons
            Button(String(localized: "sidebar.context.copyPath", bundle: .l10n)) {
                Pasteboard.writeString(model.relativePathForCopy(entry.url))
            }
            copyRemoteLinkButton
            Button(String(localized: "sidebar.context.revealInFinder", bundle: .l10n)) {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
    }

    /// 「<ホスト> リンクをコピーする」。文言は origin のホストに追随し（GitHub / GitLab /
    /// Bitbucket）、解決できないときはホスト名を含まない中立の文言にする。ここで既定の
    /// ホスト名を出すと、別のホストを使っているリポジトリで嘘の名前を見せることになる。
    ///
    /// リンクを作れない行（git 管理外・origin が無い・対応外のホスト・detached HEAD）でも
    /// 項目は隠さず無効化して見せる。隠すと機能の存在に気づけないため。無効化の理由は
    /// 出さない（`GitRepository.remoteFileLink(forFileAt:)` が nil へ畳んでいる）。
    ///
    /// 解決は body の評価時に 1 回だけ走る。`body` は右クリックでメニューを組み立てる
    /// ときにしか評価されないため（`FileListView` は各行に `.contextMenu` で付けている）、
    /// 一覧の行数分の libgit2 オープンにはならない。実測（TASK-507）: 60 行の一覧を
    /// 開いた直後の評価回数は行構築 60 回に対してここは 0 回だった。行ごとに走る形なら
    /// リポジトリオープンが行数倍でメインに載る（TASK-322 と同型）ため、ここを
    /// 非同期化するか事前解決へ移す必要が出る。
    @ViewBuilder
    private var copyRemoteLinkButton: some View {
        let link = GitRepository().remoteFileLink(forFileAt: entry.url)
        let title = Self.copyRemoteLinkTitle(
            for: link?.forge,
            format: String(localized: "sidebar.context.copyForgeLink", bundle: .l10n),
            neutralTitle: String(localized: "sidebar.context.copyRemoteLink", bundle: .l10n)
        )
        Button(title) {
            if let link { Pasteboard.writeString(link.url.absoluteString) }
        }
        .disabled(link == nil)
    }

    /// メニュー文言。ホストが分かるときだけ名前を差し込む。
    ///
    /// 文言を引数で受けるのは、`swift test` の実行環境では `Localizable.xcstrings` の
    /// 解決が効かずキー名がそのまま返るため（実測: 「Bitbucket が入る」というアサートが
    /// `"sidebar.context.copyForgeLink"` と比較されて失敗した）。localized な文字列を
    /// 内側で引くと、テストが差し込みロジックではなくバンドル解決を測ることになる。
    /// キーの存在と翻訳の有無は `/l10n-check` が別途担保する。
    static func copyRemoteLinkTitle(for forge: RemoteForge?, format: String, neutralTitle: String) -> String {
        guard let forge else { return neutralTitle }
        return String(format: format, forge.displayName)
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
                    let resolved = await withBlockingWork {
                        DirectoryLister.firstSupportedFile(in: folder)
                    }
                    if let first = resolved {
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
