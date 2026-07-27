import Foundation

/// ディレクトリ走査の結果。上限で打ち切った場合は `isTruncated` が立つ。
public struct DirectoryScanResult: Equatable, Sendable {
    public let files: [URL]
    /// 深さまたは件数の上限に達して走査を打ち切ったか。
    /// 呼び出し元は「候補が全部ではない」ことを表示に反映する(黙って切り捨てない)。
    public let isTruncated: Bool

    public init(files: [URL], isTruncated: Bool) {
        self.files = files
        self.isTruncated = isTruncated
    }
}

/// git 管理外のディレクトリから候補ファイルを集める再帰走査。
///
/// git 管理下では `GitFileIndexing` の追跡ファイルを使うため、この型は
/// そのフォールバックにあたる。無制限に潜ると巨大なツリーで固まるため、
/// 深さと件数の上限、および除外ディレクトリを必ず持つ。
public struct DirectoryFileScanner: Sendable {
    private let maximumDepth: Int
    private let maximumCount: Int
    private let excludedDirectoryNames: Set<String>

    /// - Parameters:
    ///   - maximumDepth: 潜る深さの上限。ルート直下を 1 と数える。
    ///   - maximumCount: 集めるファイル数の上限。
    ///   - excludedDirectoryNames: 中身を見ないディレクトリ名。隠し設定とは独立に常に除外する。
    public init(
        maximumDepth: Int = 8,
        maximumCount: Int = 10000,
        excludedDirectoryNames: Set<String> = [".git", "node_modules", ".build"]
    ) {
        self.maximumDepth = maximumDepth
        self.maximumCount = maximumCount
        self.excludedDirectoryNames = excludedDirectoryNames
    }

    /// `root` 以下のファイルを深さ優先で集める。
    ///
    /// 各ディレクトリの中身を名前順に並べてから潜るため、上限で打ち切った場合でも
    /// 結果は入力ツリーだけで決まる(同じツリーなら常に同じ並び・同じ打ち切り位置)。
    /// 並べ替えにはロケール非依存の比較を使い、実行環境で順序が変わらないようにする。
    public func scan(root: URL, includingHiddenFiles: Bool) -> DirectoryScanResult {
        var state = WalkState()
        walk(directory: root, depth: 1, includingHiddenFiles: includingHiddenFiles, state: &state)
        return DirectoryScanResult(files: state.files, isTruncated: state.isTruncated)
    }

    // MARK: - Private

    private struct WalkState {
        var files: [URL] = []
        var isTruncated = false
        /// 件数上限に達したか。深さ上限と違い、こちらは走査全体を止める。
        var hasReachedCountLimit = false
    }

    /// 深さ上限は「その枝をこれ以上潜らない」だけで、兄弟や親の残りの走査は続ける。
    /// 件数上限に達した場合のみ走査全体を打ち切る。両者を混ぜると、深い枝が 1 本
    /// あるだけでそれ以降のファイルが丸ごと欠ける。
    private func walk(directory: URL, depth: Int, includingHiddenFiles: Bool, state: inout WalkState) {
        guard depth <= maximumDepth else {
            state.isTruncated = true
            return
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            // 「存在するのに列挙できない」(権限なし等)は候補を黙って切り捨てない方針に従い
            // truncated 扱いにし、末尾の打ち切り表示で「ここに出ていないものがある」と伝える。
            // 存在しないディレクトリは切り捨てではなく単に空なので truncated にしない。
            if FileManager.default.fileExists(atPath: directory.path) {
                state.isTruncated = true
            }
            return
        }

        for entry in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !state.hasReachedCountLimit else { return }
            let name = entry.lastPathComponent
            if !includingHiddenFiles, HiddenFileRule.isHidden(component: name) { continue }

            if isTraversableDirectory(entry) {
                guard !excludedDirectoryNames.contains(name) else { continue }
                walk(
                    directory: entry,
                    depth: depth + 1,
                    includingHiddenFiles: includingHiddenFiles,
                    state: &state
                )
                continue
            }

            guard state.files.count < maximumCount else {
                state.hasReachedCountLimit = true
                state.isTruncated = true
                return
            }
            state.files.append(entry)
        }
    }

    /// 潜ってよいディレクトリか。シンボリックリンクは実体を追わず、リンクそのものを
    /// 1 件のファイル候補として扱う(ツリーが循環しても走査が止まらなくなるため)。
    private func isTraversableDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true
        else { return false }
        return values.isDirectory == true
    }
}
