import AppKit
import BefoldKit
import Foundation

/// ReferenceResolutionCoordinator が現在ファイルの参照と遷移を委譲する先。
/// ViewerWindowController が実装する。循環参照を避けるためコーディネータからは weak 参照する。
@MainActor
protocol ReferenceResolutionHost: AnyObject {
    /// 参照解決の基準になる、現在表示中のファイル URL。
    /// 切替・リネームで変化するため都度参照する。
    var referenceBaseURL: URL { get }
    /// 解決できたパス参照を開く。
    func openReference(_ url: URL, disposition: OpenDisposition)
    /// 解決できなかったパス参照をユーザーに知らせる。
    func presentReferenceNotFound(url: URL)
}

/// git 連携を持たない索引。パス参照は相対解決だけで済ませる。
///
/// ViewerWindowController の既定値として、`git` を起動しないことを保証するために使う。
/// 本番の共有インスタンス(GitCommandFileIndex)は ViewerWindowManager から注入される。
struct DisabledGitFileIndex: GitFileIndexing {
    func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
        nil
    }
}

/// パス参照の解決に関わる関心(索引の先読み・クリック時のオープン・表示時の一括解決)をまとめる。
/// 遷移そのものと「見つかりません」表示は host(ViewerWindowController)へ委譲する。
@MainActor
final class ReferenceResolutionCoordinator {
    /// git 追跡ファイルの索引。本番では全ウィンドウで 1 個を共有する。
    private let gitIndex: any GitFileIndexing
    /// パス参照の解決器。表示時とクリック時で同じものを通すことが「リンク化した参照は
    /// 必ずそのリンク先へ開ける」という不変条件の根拠。テストから差し替えられるよう var にする。
    var resolver: TrackedPathResolver

    /// 遷移・現在ファイル参照の委譲先。循環参照を避けるため weak。
    private weak var host: ReferenceResolutionHost?

    /// 直近のクリック解決タスク。テストが完了を待つためのシーム(SidebarNavigator.pendingBaseDirectoryTask
    /// と同じ方針)。呼び出し元が結果を待つ必要はないため戻り値は使わない。
    private(set) var pendingOpenReferenceTask: Task<Void, Never>?

    init(host: ReferenceResolutionHost, fileReader: any FileReading, gitIndex: any GitFileIndexing) {
        self.host = host
        self.gitIndex = gitIndex
        resolver = TrackedPathResolver(fileReader: fileReader, gitIndex: gitIndex)
    }

    /// 表示中ファイルの属するリポジトリの索引を先読みし、解決要求時のキャッシュ命中を狙う。
    func warm(forFileAt url: URL) {
        gitIndex.warm(forFileAt: url)
    }

    /// リンク/パス参照のアクティベーションを処理する。
    /// 解決はキャッシュ未命中時に `git ls-files` の subprocess を待つため、resolveReferences と
    /// 同じ方針で MainActor を離して行い、host への通知だけメインアクターへ戻す。
    func handleOpenReference(href: String, disposition: OpenDisposition) {
        guard let host else { return }
        let resolver = resolver
        let baseURL = host.referenceBaseURL
        pendingOpenReferenceTask = Task {
            let reference = await Task.detached(priority: .userInitiated) {
                resolver.resolve(href: href, baseURL: baseURL)
            }.value
            guard let host = self.host else { return }
            switch reference {
            case let .external(url):
                NSWorkspace.shared.open(url)
            case let .resolved(url):
                host.openReference(url, disposition: disposition)
            case .unresolved:
                // 解決できなかったパスは、素朴な相対解決結果を「見つかりません」表示に使う。
                if case let .localFile(url) = ReferenceResolver.resolve(href: href, baseURL: baseURL) {
                    host.presentReferenceNotFound(url: url)
                }
            case .ignored:
                break
            }
        }
    }

    /// パス参照群を解決し、実在するものだけ「書かれたパス→解決済み絶対パス」で返す(表示時解決用)。
    /// クリック時の handleOpenReference と同じ resolver を使うため、リンク化した参照は
    /// 必ず同じ URL へ開く(解決の単一情報源)。
    ///
    /// 解決はキャッシュ未命中時に `git ls-files` の subprocess を待つため、MainActor 上では
    /// 走らせない(大きなリポジトリで数百 ms の停止になる)。要求時点の resolver と
    /// baseURL を捕捉してバックグラウンドで解決する。解決中にファイルが切り替わっても、
    /// 捕捉した baseURL は「その要求を出した表示内容」の基準ディレクトリのままなので、
    /// リンク化とクリック時の遷移先が食い違うことはない(切替時は JS 側が未応答バッチを
    /// 空にするため、遅れて届いた応答は何にも適用されない)。
    func resolveReferences(_ paths: [String]) async -> [String: String] {
        guard let host else { return [:] }
        let resolver = resolver
        let baseURL = host.referenceBaseURL
        return await Task.detached(priority: .userInitiated) {
            var result: [String: String] = [:]
            // バッチ一括で解決し、git 追跡ファイルの索引構築を 1 度に抑える。
            for (path, reference) in resolver.resolveAll(hrefs: paths, baseURL: baseURL) {
                if case let .resolved(url) = reference {
                    result[path] = url.path
                }
            }
            return result
        }.value
    }
}
