import AppKit
import SwiftUI

/// サイドバー(FileListView)とプレビュー内フォルダー一覧(FolderListingView)が
/// 共有する行表示。ここを一箇所にすることで両者の見た目の基準を一致させる。
struct FileListEntryRow: View {
    let entry: FileListEntry
    /// この行の git 状態を返すクロージャ。バッジを出さない画面(FolderListingView)は既定の nil。
    ///
    /// 状態そのものではなくクロージャを受け取るのは、`List` の行ビルダーが
    /// (NSTableView 裏打ちのため)遅延評価され、呼び出し側で `model.gitStatuses` を読むと
    /// 観測トラッキングのスコープ外になるため。**body の中で評価**することで行ごとに
    /// 観測が登録され、状態マップだけを差し替えても行が描き直される。
    var gitStatus: (() -> GitFileStatus?)?
    /// このフォルダー行の配下(再帰的)の git 状態を返すクロージャ。`gitStatus` と同じ理由で
    /// 状態そのものではなくクロージャを受け取り、body の中で評価する。
    var gitFolderStatus: (() -> GitFolderStatus?)?

    /// フォルダー行のバッジ。配下に変更が無ければ nil。
    private func folderBadgeAppearance() -> GitStatusBadge.Appearance? {
        guard let status = gitFolderStatus?() else { return nil }
        return GitStatusBadge.appearance(forFolder: status)
    }

    var body: some View {
        // インデントは行の**中身**へ入れる。ヒット領域は呼び出し側が
        // `.padding(...).contentShape(.rect)` で行の外側に張っており(FileListView)、
        // 行ビュー自体の幅はここでの leading 分では変わらないため、インデントした
        // 子行でも行全幅のダブルクリックが従来どおり効く。
        // ドリルダウン表示では depth が全て 0 なので 0pt となり見た目は変わらない。
        HStack(spacing: 2) {
            disclosureIndicator
            content
        }
        .padding(.leading, SidebarRowIndent.leadingInset(forDepth: entry.depth))
    }

    /// ツリー表示のフォルダ行の開閉三角。`entry.disclosure` が nil のとき
    /// (ドリルダウン表示・プレビュー内のフォルダー一覧・ファイル行)は何も出さないので、
    /// 従来の見た目がそのまま保たれる。
    @ViewBuilder
    private var disclosureIndicator: some View {
        switch entry.disclosure {
        case .none:
            EmptyView()
        case .collapsed:
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
        case .loadingChildren:
            // 「展開したが子がまだ届いていない」。空のフォルダ(下向きの三角)と
            // 見た目で区別できるようにする。
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12)
        case .expanded:
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
        case .expandedEmpty:
            // 開いたが見えるものが無い。三角は下向きのまま薄くする。
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12)
        case .expandedFailed:
            // 列挙に失敗した。空のフォルダ(薄い下向き三角)と取り違えられないよう、
            // 三角ではなく警告の記号を出す。理由は help に出す。
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .help(String(localized: "folder.enumerationFailed", bundle: .l10n))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .parentNavigation:
            HStack {
                Label {
                    Text("..")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "arrow.up.doc")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .folder:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
                if let appearance = folderBadgeAppearance() {
                    GitStatusBadgeView(appearance: appearance)
                }
                if entry.disclosure == nil {
                    // ドリルダウン表示でのみ「この行を開くと下の階層へ移動する」を示す。
                    // ツリー表示では左の開閉三角が同じ役割を担うため出さない(Finder と同じ)。
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .help(entry.url.lastPathComponent)
        case .file:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(entry.hasUnknownExtension ? .secondary : .primary)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
                if let status = gitStatus?(), let appearance = GitStatusBadge.appearance(for: status) {
                    GitStatusBadgeView(appearance: appearance)
                }
            }
            .help(entry.url.lastPathComponent)
        }
    }
}
