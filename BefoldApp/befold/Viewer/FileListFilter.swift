import BefoldKit
import Foundation

/// 一覧に適用する表示絞り込み。サイドバー(FileListModel.visibleEntries)と
/// プレビューのフォルダー一覧(FolderListingView)が **同じ値を同じ関数で** 適用するための型。
///
/// 絞り込みの条件をここに 1 つだけ集めるのが要点。以前はプレビュー側に
/// sortOrder と showHiddenFiles だけを個別に渡しており、あとから足した
/// 「変更のみ表示」がサイドバーにしか効かず、1 ウィンドウ内に 2 つの答えが並んでいた
/// (TASK-288)。設定が増えるときはこの型に足せば両方へ同時に届く。
struct FileListFilter: Equatable {
    /// ファイル名フィルターの検索文字列。空なら名前での絞り込みはしない。
    var filterText: String = ""
    /// 「変更のみ表示」が ON のときの git 状態。OFF・git 管理外・取得失敗・機能無効なら nil。
    /// **変更が 1 つも無いリポジトリは「空の状態」であって nil ではない**(TASK-285)。
    var gitStatus: SidebarGitStatus?
    /// いま提示している行の正規化パスキー。git 絞り込みでは変更が無くてもこの行を残す。
    ///
    /// `filterText` はユーザーが自分で打った条件なので、一致しない行が消えるのは納得できる。
    /// 一方 git 絞り込みは状態由来で消えるため、開いている文書が黙って一覧から消え、
    /// 選択ハイライトと矢印キー移動が一覧と食い違う(TASK-286)。
    var presentedPathKey: String?

    /// `directory` 直下の一覧に絞り込みを適用する。
    /// `.parentNavigation` は条件に関わらず常に残す(上位フォルダへの移動手段を消さないため)。
    func apply(to entries: [FileListEntry], in directory: URL) -> [FileListEntry] {
        let gitFilter = gitChangeFilter(for: directory)
        guard !filterText.isEmpty || gitFilter != nil else { return entries }
        return entries.filter { entry in
            guard entry.kind != .parentNavigation else { return true }
            guard filterText.isEmpty
                || WildcardMatcher.matches(pattern: filterText, in: entry.url.lastPathComponent)
            else { return false }
            guard let gitFilter else { return true }
            return gitFilter.hasChange(at: entry.pathKey) || entry.pathKey == presentedPathKey
        }
    }

    /// `directory` に適用できる git 絞り込み。状態が別のディレクトリのものなら nil を返す。
    ///
    /// 一覧の取得と git の取得は別タスクで走り完了順が保証されないため、移動直後に
    /// 前のリポジトリの状態で絞り込むと一覧が一瞬消える(TASK-285)。同じ判定が、
    /// 選択中のサブフォルダーをプレビューしている場合(状態は表示中ディレクトリのもので、
    /// そのサブフォルダー配下の行とは突き合わせられない)の無効化も兼ねる。
    func gitChangeFilter(for directory: URL) -> SidebarGitStatus? {
        guard let gitStatus, gitStatus.directoryKey == directory.normalizedPathKey else {
            return nil
        }
        return gitStatus
    }
}
