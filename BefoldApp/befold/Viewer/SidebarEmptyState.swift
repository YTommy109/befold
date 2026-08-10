import SwiftUI

/// 一覧が空のときの案内。サイドバー(FileListView)とプレビュー内フォルダー一覧
/// (FolderListingView)が **同じ 1 つの実装** を使う。
///
/// 空になった理由で文言を変えるのが要点。「変更のみ表示」で空になった場合に
/// 「対応ファイルがありません」と出すと、開ける文書で満たされたフォルダーでも
/// 読み込みに失敗したように読める(TASK-287)。絞り込みが効いていること自体を伝え、
/// 解除すれば見えると分かる文言にする。
///
/// 2 箇所に同じ出し分けを書き分けない。以前はサイドバーだけが理由で出し分け、
/// プレビュー側は「対応ファイルがありません」固定だった。git 絞り込みが
/// リポジトリ配下のどの階層にも効くようになった時点で(TASK-361.2)、
/// プレビューでも絞り込みによる空が起こるようになり、片側だけ直すと
/// TASK-320 と同型の取り残しになる。
struct SidebarEmptyState: View {
    /// いま効いている git 絞り込み。nil なら「対応ファイルが無い」ほうの文言になる。
    let activeGitChangeFilter: SidebarGitStatus?
    /// 「対応ファイルが無い」ほうの文言に添えるフォルダー名。
    let directoryName: String

    var body: some View {
        if activeGitChangeFilter != nil {
            ContentUnavailableView(
                String(localized: "sidebar.empty.changedFilesOnly", bundle: .l10n),
                systemImage: "arrow.triangle.branch",
                description: Text(
                    String(localized: "sidebar.empty.changedFilesOnly.description", bundle: .l10n)
                )
            )
        } else {
            ContentUnavailableView(
                String(localized: "sidebar.empty", bundle: .l10n),
                systemImage: "doc.questionmark",
                description: Text(directoryName)
            )
        }
    }
}
