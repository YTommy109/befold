import Foundation
import libgit2

/// gh-stack のスタックファイルから、現在のブランチの親ブランチ名を読む。
///
/// git はブランチの親を記録しない(`branch.*` の upstream は自分自身か main を指すだけ)。
/// 親は stacked PR ツールの記録から得る。実物の確認(gh-stack v0.1.1、TASK-353.1):
/// 配置は **worktree ごとの admin dir**(`.git/worktrees/<名前>/gh-stack`、通常の
/// チェックアウトでは `.git/gh-stack`)。新版は common dir へ寄せるため、両方を探す。
/// `gh-stack.lock` は排他用の別ファイルで読まない。
///
/// 「親が分からない」は nil で表す。縮退のしかた(デフォルトブランチへ落とす)は呼び出し側が決める。
enum GitParentBranchResolver {
    private static let stackFileName = "gh-stack"
    private static let supportedSchemaVersion = 1

    /// 開いたリポジトリの現在ブランチの親。detached HEAD・スタック外・読めない場合は nil。
    static func parentBranch(in repository: OpaquePointer) -> String? {
        guard let current = currentBranch(in: repository) else { return nil }
        // 順序: common dir(新版)→ per-worktree dir(v0.1.1)。同じパスなら 1 回だけ読む。
        var seen = Set<String>()
        for directory in [commonDirectory(of: repository), gitDirectory(of: repository)] {
            guard let directory, seen.insert(directory.path).inserted,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(stackFileName)),
                  let parent = parentBranch(of: current, inStackFile: data)
            else { continue }
            return parent
        }
        return nil
    }

    /// スタックファイルの JSON を解釈する純粋関数。
    ///
    /// `branches` は下から上の順で、親は 1 つ前の要素、先頭なら `trunk`。各要素の `base` は
    /// 使わない(隣接要素と trunk だけで決まる)。未知の schemaVersion・壊れた JSON・
    /// 現在ブランチがどのスタックにも無い場合は nil。
    static func parentBranch(of currentBranch: String, inStackFile data: Data) -> String? {
        guard let file = try? JSONDecoder().decode(StackFile.self, from: data),
              file.schemaVersion == supportedSchemaVersion
        else { return nil }
        for stack in file.stacks {
            guard let index = stack.branches.firstIndex(where: { $0.branch == currentBranch }) else { continue }
            return index == 0 ? stack.trunk.branch : stack.branches[index - 1].branch
        }
        return nil
    }

    private struct StackFile: Decodable {
        struct Branch: Decodable { let branch: String }
        struct Stack: Decodable {
            let trunk: Branch
            let branches: [Branch]
        }

        let schemaVersion: Int
        let stacks: [Stack]
    }

    private static func currentBranch(in repository: OpaquePointer) -> String? {
        var head: OpaquePointer?
        guard git_repository_head(&head, repository) == 0, let head else { return nil }
        defer { git_reference_free(head) }
        guard git_reference_is_branch(head) == 1, let name = git_reference_shorthand(head) else { return nil }
        return String(cString: name)
    }

    private static func commonDirectory(of repository: OpaquePointer) -> URL? {
        git_repository_commondir(repository).map { URL(fileURLWithPath: String(cString: $0), isDirectory: true) }
    }

    private static func gitDirectory(of repository: OpaquePointer) -> URL? {
        git_repository_path(repository).map { URL(fileURLWithPath: String(cString: $0), isDirectory: true) }
    }
}
