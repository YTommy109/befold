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
    let repositoryRootKey: String
    /// ファイル単位の状態。キーは `FileListEntry.pathKey`。
    let files: [String: GitFileStatus]
    /// フォルダー行のバッジ用に配下を集約した結果。
    let folders: [String: GitFolderStatus]
    /// 親リポジトリの `git status` では**配下を答えられない**境界のルート
    /// (サブモジュール・ネストしたリポジトリ)。
    ///
    /// ネストしたリポジトリは未追跡ディレクトリ 1 レコードに畳まれるため配下が全て
    /// 「新規」に見え、サブモジュールは 1 レコードのみで配下のファイルが一切出ないため
    /// 「変更なし」に見える。どちらも親の答えを配下へ広げると嘘になるので、
    /// **配下は「判定不能」として縮退する**(TASK-403)。
    ///
    /// 境界の行そのものは対象外。親から見た `sub` / `child/` の状態は親が答えられる。
    let indeterminateRoots: Set<String>

    init(
        repositoryRootKey: String,
        statuses: [String: GitFileStatus],
        indeterminateRoots: Set<String> = []
    ) {
        self.repositoryRootKey = repositoryRootKey
        files = statuses
        folders = GitFolderStatus.aggregate(statuses: statuses)
        self.indeterminateRoots = indeterminateRoots
    }

    /// 取得結果から表示用の状態を作る。リポジトリを解決できなかった(git 管理外・
    /// 機能無効)なら nil。**変更ゼロのリポジトリは「空の状態」であって nil ではない**。
    ///
    /// 取得元のディレクトリは受け取らない。受け取ると「このディレクトリ用の状態」という
    /// 読み方が残り、等値ガードを復活させる余地になる。対付けが要るのは
    /// `FileListModel.applyGitStatus(_:for:sequence:)` の側だけ。
    init?(result: GitStatusResult) {
        guard let root = result.repositoryRoot else { return nil }
        self.init(
            repositoryRootKey: root.normalizedPathKey,
            statuses: result.statuses,
            indeterminateRoots: result.indeterminateRoots
        )
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
        return ancestorFact(of: pathKey) == .untracked ? GitFileStatus(isUntracked: true) : nil
    }

    /// フォルダー行のバッジに使う集約。配下に変更が無ければ nil。
    ///
    /// ファイル行と同じ理由で、畳み込みの配下にあるサブフォルダーも集約を持たない。
    /// 配下が全て未追跡であることは祖先から分かるので、そのぶんだけ組み立てて返す。
    func folderStatus(at pathKey: String) -> GitFolderStatus? {
        if let status = folders[pathKey] { return status }
        return ancestorFact(of: pathKey) == .untracked ? GitFolderStatus(hasUntracked: true) : nil
    }

    /// この行に git 変更があるか(= バッジが付く行か)。
    ///
    /// 絞り込み(`FileListFilter`)とバッジ描画が食い違わないよう、**判定を持たず**
    /// バッジの引き当てそのものに委ねる。ここに独自の条件を足すと、絞り込みには
    /// 出るのにバッジが無い行が生まれる(TASK-345)。
    func hasChange(at pathKey: String) -> Bool {
        fileStatus(at: pathKey) != nil || folderStatus(at: pathKey) != nil
    }

    /// 祖先を遡って最初に見つかった「配下の扱いを決める事実」。
    ///
    /// 走査を 1 本にまとめてあるのが要点。**未追跡の畳み込みと境界は同じディレクトリで
    /// 重なる**(ネストしたリポジトリの `child/` は親から見て未追跡ディレクトリであり、
    /// 同時に境界でもある)。別々に走査して「未追跡祖先がある」を先に答えると、
    /// 子リポジトリでコミット済み・クリーンなファイルまで「新規」と表示される
    /// (TASK-403 の AC#2)。だから同じステップで境界を先に見る。
    private enum AncestorFact {
        /// 畳み込まれた未追跡ディレクトリの配下。配下は全て未追跡とみなす(TASK-285)。
        case untracked
        /// 親リポジトリが答えを持たない境界の配下。バッジは出さない。
        case indeterminate
    }

    /// 祖先の判定に `folders[ancestor]?.hasUntracked` は使えない。未追跡ファイルを 1 つ
    /// 含むだけのフォルダーでも真になり、同じフォルダー内の追跡済みで未変更のファイルまで
    /// 変更ありと誤判定するため。畳み込みの事実そのもの(`files[ancestor].isUntracked`)を見る。
    private func ancestorFact(of pathKey: String) -> AncestorFact? {
        var current = pathKey
        while let parent = Self.ancestor(of: current) {
            if indeterminateRoots.contains(parent) { return .indeterminate }
            if files[parent]?.isUntracked == true { return .untracked }
            current = parent
        }
        return nil
    }

    /// 親リポジトリが配下について何も答えていない位置か。
    ///
    /// 「変更が無い」ではなく「分からない」。絞り込み(`FileListFilter`)はこの行を
    /// 残す。残さないと、サブモジュール配下のファイルが「変更のみ表示」で黙って
    /// 全部消える(TASK-403 の AC#1)。
    func isIndeterminate(at pathKey: String) -> Bool {
        ancestorFact(of: pathKey) == .indeterminate
    }

    private static func ancestor(of pathKey: String) -> String? {
        let parent = (pathKey as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != pathKey else { return nil }
        return parent
    }
}
