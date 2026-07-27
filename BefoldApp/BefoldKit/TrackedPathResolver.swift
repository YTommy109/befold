import Foundation

/// url を含む git リポジトリの追跡ファイル索引を返す。git 管理外なら nil。
///
/// 生の URL 一覧ではなく索引を返すのは、索引の構築が候補数に比例した正規化コストを持ち、
/// 実装側でキャッシュして使い回せるようにするため(呼び出しのたびに作り直すと、
/// 大きなリポジトリでは解決バッチごとに O(候補数) の再構築が走る)。
public protocol GitFileIndexing: Sendable {
    func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex?
    /// url を含むリポジトリの作業ツリールート。git 管理外・判定不能なら nil。
    /// 追跡ファイル索引と同じ解決結果を使い回せるよう、実装は `trackedFileIndex` と
    /// ルート解決を共有する(呼び出し側が別途 rev-parse を重ねなくて済む)。
    /// git を扱わない実装(索引を持たないシーム)では既定で nil を返す。
    func repositoryRoot(forFileAt url: URL) -> URL?
    /// 解決要求より前に索引を用意しておく(ファイルを開いた/切り替えた契機で呼ぶ)。
    /// 索引の準備は最適化であって解決の前提ではないため、既定は何もしない。
    func warm(forFileAt url: URL)
}

public extension GitFileIndexing {
    func repositoryRoot(forFileAt _: URL) -> URL? {
        nil
    }

    func warm(forFileAt _: URL) {}
}

/// パス参照の解決結果。
public enum ResolvedReference: Equatable, Sendable {
    case external(URL) // http/https。リンク維持(ブラウザで開く)
    case resolved(URL) // 実在を確認できたローカルファイル
    case unresolved // ローカルパスだが解決できなかった(リンクにしない)
    case ignored // 空 / #anchor / 未対応スキーム(据え置き)
}

/// 「相対/絶対で実在 → git 追跡ファイルへの構成要素サフィックス一致(近さ最小)」の順で
/// パス参照を解決する。表示時(リンク化判定)とクリック時(オープン)の両方から使う単一情報源。
public struct TrackedPathResolver: Sendable {
    private let fileReader: FileReading
    private let gitIndex: GitFileIndexing

    public init(fileReader: FileReading = DefaultFileReader(), gitIndex: GitFileIndexing) {
        self.fileReader = fileReader
        self.gitIndex = gitIndex
    }

    /// 単一の参照を解決する(クリック時のオープン用)。
    /// 複数の参照をまとめて解決する場合は、git 索引の取得を 1 度に抑える `resolveAll` を使う。
    public func resolve(href: String, baseURL: URL) -> ResolvedReference {
        var index = LazySuffixIndex(gitIndex: gitIndex, baseURL: baseURL)
        return resolve(href: href, baseURL: baseURL, index: &index)
    }

    /// 複数の参照を一括解決する(表示時解決のバッチ用)。
    /// git 追跡ファイル索引の取得をバッチ全体で 1 度に抑えるため、参照数に比例した
    /// 再計算が起きない。重複する href は 1 度だけ解決する。
    public func resolveAll(hrefs: [String], baseURL: URL) -> [String: ResolvedReference] {
        var index = LazySuffixIndex(gitIndex: gitIndex, baseURL: baseURL)
        var result: [String: ResolvedReference] = Dictionary(minimumCapacity: hrefs.count)
        for href in hrefs where result[href] == nil {
            result[href] = resolve(href: href, baseURL: baseURL, index: &index)
        }
        return result
    }

    private func resolve(
        href: String, baseURL: URL, index: inout LazySuffixIndex
    ) -> ResolvedReference {
        switch ReferenceResolver.resolve(href: href, baseURL: baseURL) {
        case let .external(url):
            return .external(url)
        case .unsupported:
            return .ignored
        case let .localFile(url):
            if fileReader.isExistingFile(at: url) {
                return .resolved(url)
            }
            // git の索引は worktree の実態と一致しない。削除済みで index にだけ残る
            // ファイルや submodule の gitlink(実体はディレクトリ)も列挙されるため、
            // 一致した候補も実在を確かめてからでないと開けないリンクを作ってしまう。
            guard let written = ReferenceResolver.localPathString(from: href),
                  let candidates = index.value(),
                  let match = candidates.bestMatch(writtenPath: written, baseURL: baseURL),
                  fileReader.isExistingFile(at: match)
            else { return .unresolved }
            return .resolved(match)
        }
    }

    /// git 追跡ファイルの索引を、実際に git フォールバックが要るまで取りに行かず、
    /// 要った場合もバッチ内で 1 度だけ取得する遅延ホルダ。
    /// 相対解決だけで片付く一般的な文書では git 索引に触れない。
    private struct LazySuffixIndex {
        private let gitIndex: GitFileIndexing
        private let baseURL: URL
        private var isLoaded = false
        private var index: SuffixPathIndex?

        init(gitIndex: GitFileIndexing, baseURL: URL) {
            self.gitIndex = gitIndex
            self.baseURL = baseURL
        }

        /// git 管理外(追跡ファイルを取得できない)なら nil。
        mutating func value() -> SuffixPathIndex? {
            if !isLoaded {
                isLoaded = true
                index = gitIndex.trackedFileIndex(forFileAt: baseURL)
            }
            return index
        }
    }
}
