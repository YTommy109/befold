import Foundation

/// サイドバー 1 画面ぶんの git 状態。バッジ描画と「変更のみ表示」の絞り込みが
/// 同じ 1 つの値を見るための入れ物で、git は一切呼ばない純粋な写像。
///
/// この型が存在すること自体が「リポジトリを解決でき、状態を取れた」という事実を表す。
/// 非 git ディレクトリ・取得失敗・機能無効のときは `FileListModel.gitStatus` を nil に
/// しておき、絞り込み側は値の中身(空かどうか)ではなく nil かどうかで判断する。
/// 中身で判断すると「変更が 1 つも無い git リポジトリ」を非 git と取り違える(TASK-285)。
struct SidebarGitStatus: Equatable, Sendable {
    /// この状態が適用できる範囲 = 解決できたリポジトリルートの正規化パスキー。
    ///
    /// **取得したディレクトリではなくリポジトリルートを持つ**のが要点。`files` は
    /// 元からリポジトリ全体ぶんの絶対パスキーなので(GitStatusReader が
    /// `root.appendingPathComponent(相対パス).normalizedPathKey` で詰める)、
    /// ルート配下ならどの階層の行でも引ける。取得したディレクトリと等値で
    /// 突き合わせていた頃は、複数階層を同時に表示すると 1 つの階層にしか
    /// 絞り込みが効かなかった(TASK-361.2)。
    ///
    /// 「一覧の取得と git の取得の完了順が保証されない」ことへの手当ては、この値では
    /// なく `FileListModel.applyGitStatus(_:for:sequence:)` の発行順序 + ディレクトリ
    /// 対付けが担う(TASK-285 / TASK-293)。**2 つは役割が違う**。こちらは
    /// 「どの行に適用できるか」、あちらは「どの一覧の取得と対か」。
    ///
    /// - Note: ネストしたリポジトリ・サブモジュールの配下は、親リポジトリの
    ///   `git status` では正しく答えられない。ネストしたリポジトリは未追跡
    ///   ディレクトリ 1 レコードに畳まれるため配下が全て「新規」に見え、
    ///   サブモジュールは 1 レコードのみで配下のファイルが一切出ないため
    ///   「変更なし」に見える(TASK-403 で扱う)。
    let repositoryRootKey: String
    /// ファイル単位の状態。キーは `FileListEntry.pathKey`。
    let files: [String: GitFileStatus]
    /// フォルダー行のバッジ用に配下を集約した結果。
    let folders: [String: GitFolderStatus]

    init(repositoryRootKey: String, statuses: [String: GitFileStatus]) {
        self.repositoryRootKey = repositoryRootKey
        files = statuses
        folders = GitFolderStatus.aggregate(statuses: statuses)
    }

    /// 取得結果から表示用の状態を作る。リポジトリを解決できなかった(git 管理外・
    /// 機能無効)なら nil。**変更ゼロのリポジトリは「空の状態」であって nil ではない**。
    ///
    /// 取得元のディレクトリは受け取らない。受け取ると「このディレクトリ用の状態」という
    /// 読み方が残り、等値ガードを復活させる余地になる。対付けが要るのは
    /// `FileListModel.applyGitStatus(_:for:sequence:)` の側だけ。
    init?(result: GitStatusResult) {
        guard let root = result.repositoryRoot else { return nil }
        self.init(repositoryRootKey: root.normalizedPathKey, statuses: result.statuses)
    }

    /// `directory` がこの状態の適用範囲(リポジトリルート配下)か。
    ///
    /// 区切り文字 `/` を含めて比較するのは、前方一致だけの兄弟パス
    /// (ルートが `/repo` のときの `/repo2`)を誤って含めないため。
    /// 規則は `DirectoryLister.isWithinHome(_:home:)` と同じ。
    func covers(_ directory: URL) -> Bool {
        let target = directory.normalizedPathKey
        return target == repositoryRootKey || target.hasPrefix(repositoryRootKey + "/")
    }

    /// ファイル行のバッジに使う状態。変更が無ければ nil。
    ///
    /// 畳み込み(下記)の配下は `files` にキーを持たないため、辞書を引くだけでは
    /// バッジが出ない。祖先が未追跡なら、その配下も未追跡として組み立てて返す。
    func fileStatus(at pathKey: String) -> GitFileStatus? {
        if let status = files[pathKey] { return status.isClean ? nil : status }
        return hasUntrackedAncestor(of: pathKey) ? GitFileStatus(isUntracked: true) : nil
    }

    /// フォルダー行のバッジに使う集約。配下に変更が無ければ nil。
    ///
    /// ファイル行と同じ理由で、畳み込みの配下にあるサブフォルダーも集約を持たない。
    /// 配下が全て未追跡であることは祖先から分かるので、そのぶんだけ組み立てて返す。
    func folderStatus(at pathKey: String) -> GitFolderStatus? {
        if let status = folders[pathKey] { return status }
        return hasUntrackedAncestor(of: pathKey) ? GitFolderStatus(hasUntracked: true) : nil
    }

    /// この行に git 変更があるか(= バッジが付く行か)。
    ///
    /// 絞り込み(`FileListFilter`)とバッジ描画が食い違わないよう、**判定を持たず**
    /// バッジの引き当てそのものに委ねる。ここに独自の条件を足すと、絞り込みには
    /// 出るのにバッジが無い行が生まれる(TASK-345)。
    func hasChange(at pathKey: String) -> Bool {
        fileStatus(at: pathKey) != nil || folderStatus(at: pathKey) != nil
    }

    /// 畳み込まれた未追跡ディレクトリの配下か。
    ///
    /// porcelain の既定(`-unormal`)は未追跡ディレクトリを `dir/` の 1 レコードへ畳むため、
    /// 新規フォルダー配下は `files` にも `folders` にもキーを持たない。祖先が未追跡
    /// ディレクトリとして記録されていれば、その配下は全て未追跡とみなす(TASK-285)。
    ///
    /// 祖先の判定に `folders[ancestor]?.hasUntracked` は使えない。未追跡ファイルを 1 つ
    /// 含むだけのフォルダーでも真になり、同じフォルダー内の追跡済みで未変更のファイルまで
    /// 変更ありと誤判定するため。畳み込みの事実そのもの(`files[ancestor].isUntracked`)を見る。
    private func hasUntrackedAncestor(of pathKey: String) -> Bool {
        var current = pathKey
        while let parent = Self.ancestor(of: current) {
            if files[parent]?.isUntracked == true { return true }
            current = parent
        }
        return false
    }

    private static func ancestor(of pathKey: String) -> String? {
        let parent = (pathKey as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != pathKey else { return nil }
        return parent
    }
}
