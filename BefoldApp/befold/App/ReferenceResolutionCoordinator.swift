import AppKit
import BefoldKit
import Foundation

/// 解決結果をウィンドウの操作へ繋ぐ 3 つの処理。
///
/// プロトコルにしてウィンドウコントローラへ準拠を足すのではなく、値として渡す
/// （準拠を増やすと「この型は何であるか」が読みにくくなる／TASK-441）。
/// 束ねているのは、3 つが常に同じ 1 つのウィンドウを指し、個別に差し替える意味が無いため。
/// 各クロージャはウィンドウを弱参照で捕捉すること（循環参照を避ける）。
@MainActor
struct ReferenceActions {
    /// 解決できたパス参照を開く。
    let open: (URL, OpenDisposition) -> Void
    /// 外部 URL(http/https)をブラウザで開く。
    ///
    /// `NSWorkspace.shared.open` をここで直に呼ばないのは、解決(git subprocess)を待つ間に
    /// ウィンドウが閉じられても、他の分岐と同じく抑止されるようにするため。分岐ごとに
    /// 生存確認を書くのではなく、すべての届け先をウィンドウ弱参照のクロージャに揃えることで
    /// 「閉じた後に効く操作」が構造的に起きない形にする(TASK-449)。
    let openExternal: (URL) -> Void
    /// 解決できなかったパス参照をユーザーに知らせる。
    let presentNotFound: (URL) -> Void
    /// 解決できたパス参照/外部 URL に対するコンテキストメニューを表示する。
    let presentContextMenu: (URL, Bool) -> Void
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
/// 遷移そのものと「見つかりません」表示は `ReferenceActions` 経由でウィンドウへ委譲する。
@MainActor
final class ReferenceResolutionCoordinator {
    /// git 追跡ファイルの索引。本番では全ウィンドウで 1 個を共有する。
    private let gitIndex: any GitFileIndexing
    /// パス参照の解決器。表示時とクリック時で同じものを通すことが「リンク化した参照は
    /// 必ずそのリンク先へ開ける」という不変条件の根拠。テストから差し替えられるよう var にする。
    var resolver: TrackedPathResolver

    /// 解決結果の届け先。
    private let actions: ReferenceActions
    /// 参照解決の基準になる、現在表示中のファイル URL。
    /// 切替・リネームで変化するため都度参照する（ウィンドウ解放後は nil）。
    private let baseURL: () -> URL?

    /// 直近のクリック解決タスク。テストが完了を待つためのシーム(SidebarNavigator.pendingBaseDirectoryTask
    /// と同じ方針)。呼び出し元が結果を待つ必要はないため戻り値は使わない。
    private(set) var pendingOpenReferenceTask: Task<Void, Never>?

    init(
        baseURL: @escaping () -> URL?, actions: ReferenceActions,
        fileReader: any FileReading, gitIndex: any GitFileIndexing
    ) {
        self.baseURL = baseURL
        self.actions = actions
        self.gitIndex = gitIndex
        resolver = TrackedPathResolver(fileReader: fileReader, gitIndex: gitIndex)
    }

    /// 表示中ファイルの属するリポジトリの索引を先読みし、解決要求時のキャッシュ命中を狙う。
    func warm(forFileAt url: URL) {
        gitIndex.warm(forFileAt: url)
    }

    /// リンク/パス参照のアクティベーションを処理する。
    /// 解決はキャッシュ未命中時に `git ls-files` の subprocess を待つため、resolveReferences と
    /// 同じ方針で MainActor を離して行い、ウィンドウへの通知だけメインアクターへ戻す。
    func handleOpenReference(href: String, disposition: OpenDisposition) {
        guard let baseURL = baseURL() else { return }
        let resolver = resolver
        pendingOpenReferenceTask = Task {
            let reference = await Task.detached(priority: .userInitiated) {
                resolver.resolve(href: href, baseURL: baseURL)
            }.value
            switch reference {
            case let .external(url):
                actions.openExternal(url)
            case let .resolved(url):
                actions.open(url, disposition)
            case .unresolved:
                // 解決できなかったパスは、素朴な相対解決結果を「見つかりません」表示に使う。
                if case let .localFile(url) = ReferenceResolver.resolve(href: href, baseURL: baseURL) {
                    actions.presentNotFound(url)
                }
            case .ignored:
                break
            }
        }
    }

    /// コンテキストメニュー要求を処理する。解決できない参照ではメニューを出さない
    /// (クリックが無反応なのと揃える)。
    func handleContextMenu(href: String) {
        guard let baseURL = baseURL() else { return }
        let resolver = resolver
        Task {
            let reference = await Task.detached(priority: .userInitiated) {
                resolver.resolve(href: href, baseURL: baseURL)
            }.value
            switch reference {
            case let .external(url):
                actions.presentContextMenu(url, true)
            case let .resolved(url):
                actions.presentContextMenu(url, false)
            case .unresolved, .ignored:
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
        guard let baseURL = baseURL() else { return [:] }
        let resolver = resolver
        return await Task.detached(priority: .userInitiated) {
            // バッチ一括で解決し、git 追跡ファイルの索引構築を 1 度に抑える。
            // 解決できたものだけを残す(未解決は JS 側へ渡さない)。
            resolver.resolveAll(hrefs: paths, baseURL: baseURL).compactMapValues { reference in
                if case let .resolved(url) = reference { url.path } else { nil }
            }
        }.value
    }
}
