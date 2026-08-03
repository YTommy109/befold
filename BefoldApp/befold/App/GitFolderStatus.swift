import Foundation

/// フォルダー配下(再帰的)に存在する git 変更の集約。
///
/// ファイル 1 個の状態(`GitFileStatus`)と違い、バッジ文字にできる「変更種別」は決まらない
/// (配下に別々の種別が混在しうる)。そのため種別ごとの有無だけを持ち、表示層が
/// 1 個のバッジへ写像する。
struct GitFolderStatus: Equatable, Sendable {
    var hasStaged = false
    var hasUnstaged = false
    var hasUntracked = false
    var hasBranchModified = false

    /// ファイル単位の状態マップから、フォルダーの正規化パスキー → 集約 を作る。
    ///
    /// git は一切呼ばない。`GitStatusSnapshot.statuses` はリポジトリルート配下の全変更を
    /// 持っているため、追加のプロセス起動なしにこの写像だけで求まる。
    ///
    /// 各エントリを **自身のパスキーと全祖先ディレクトリ**へ OR 集約する。自身も含めるのは、
    /// porcelain の既定(`-unormal`)が未追跡ディレクトリを `dir/` の 1 エントリに畳むため。
    /// 畳まれたディレクトリは配下のファイルが列挙されず、祖先だけへ集約するとそのフォルダー
    /// 自身がバッジ対象から漏れる。ファイルのパスキーもマップに入るが、フォルダー行しか
    /// この写像を引かないため実害はない。
    static func aggregate(statuses: [String: GitFileStatus]) -> [String: GitFolderStatus] {
        var result: [String: GitFolderStatus] = [:]
        for (pathKey, status) in statuses where !status.isClean {
            for folderKey in sequence(first: pathKey, next: ancestor(of:)) {
                result[folderKey, default: GitFolderStatus()].merge(status)
            }
        }
        return result
    }

    /// 親ディレクトリのパスキー。ルート(`/`)まで来たら終わり。
    private static func ancestor(of pathKey: String) -> String? {
        let parent = (pathKey as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != pathKey else { return nil }
        return parent
    }

    /// ファイル 1 個の状態を取り込む。
    private mutating func merge(_ status: GitFileStatus) {
        hasStaged = hasStaged || status.indexChange != nil
        hasUnstaged = hasUnstaged || status.worktreeChange != nil
        hasUntracked = hasUntracked || status.isUntracked
        hasBranchModified = hasBranchModified || status.isBranchModified
    }
}
