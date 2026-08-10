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
    ///
    /// - Note: ツリー表示では、この例外で残った行の**祖先フォルダも残る**
    ///   (`SidebarTreeFilter.keepingAncestors`)。祖先は変更を持たないので
    ///   「変更のみ表示」が ON でも未変更のフォルダ行が出るが、これは意図した例外。
    ///   残さないと親だけが消えて、開いている文書の行が孤児になる。
    ///
    /// - Note: git 絞り込みで行を残す例外はもう 1 つある。サブモジュール・ネストした
    ///   リポジトリの配下(`SidebarGitStatus.isIndeterminate(at:)`)は、親リポジトリが
    ///   「変更が無い」とは言っていない = 何も言っていないため残す(TASK-403)。
    ///   どちらの例外も `hasChange` には足さない。バッジの引き当てと絞り込みが
    ///   食い違わないための不変条件を壊すため(TASK-345)。
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
            guard !gitFilter.hasChange(at: entry.pathKey) else { return true }
            // 「変更が無い」ではなく「親リポジトリが答えを持たない」行は残す。
            // 消すと、サブモジュール配下のファイルが変更していても全部消える(TASK-403)。
            return gitFilter.isIndeterminate(at: entry.pathKey) || entry.pathKey == presentedPathKey
        }
    }

    /// `directory` に適用できる git 絞り込み。状態が別のリポジトリのものなら nil を返す。
    ///
    /// 判定は **リポジトリルート配下かどうか**(`SidebarGitStatus.covers(_:)`)。状態は
    /// リポジトリ全体ぶんの絶対パスキーを持つので、ルート配下ならどの階層の行でも
    /// 突き合わせられる。選択中のサブフォルダーをプレビューしている場合も、同じ
    /// リポジトリ内なら同じ絞り込みが効く(サイドバーとプレビューで答えを 1 つにする
    /// TASK-288 の方針。以前は等値判定でここだけ絞り込みが外れていた)。
    ///
    /// 移動直後に前のリポジトリの状態で絞り込んで一覧が一瞬消える問題(TASK-285)への
    /// 手当ては**この関数ではない**。`FileListModel.applyGitStatus(_:for:sequence:)` の
    /// 発行順序 + ディレクトリ対付けが担う。ここを等値へ戻して二重に守ろうとすると、
    /// 複数階層の絞り込みが 1 階層ぶんへ縮む(TASK-361.2)。
    func gitChangeFilter(for directory: URL) -> SidebarGitStatus? {
        guard let gitStatus, gitStatus.covers(directory) else { return nil }
        return gitStatus
    }
}
