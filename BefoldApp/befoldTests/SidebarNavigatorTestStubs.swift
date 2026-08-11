@testable import befold
import Foundation

/// `SidebarGitReading` のテスト用実装(TASK-442.6)。
///
/// プロダクトの依存は 1 つのプロトコルに畳んであるが、テストは経路ごとに別々の答えを
/// 返させたいのでクロージャで受ける。既定はどちらも「git 無し」で、必要な側だけ渡せばよい。
@MainActor
struct SidebarGitReadingStub: SidebarGitReading {
    var repositoryRoot: (URL) async -> URL? = { _ in nil }
    var statuses: (URL, GitStatusRefreshPolicy) async -> GitStatusResult = { _, _ in .empty }

    func repositoryRoot(forDirectoryAt url: URL) async -> URL? {
        await repositoryRoot(url)
    }

    func statuses(forDirectoryAt url: URL, policy: GitStatusRefreshPolicy) async -> GitStatusResult {
        await statuses(url, policy)
    }
}

/// SidebarNavigator の unit テストが共通で使うダミー host。
/// SidebarNavigatorHost は befold 内部 protocol のため BefoldTestSupport には置けない。
/// SidebarNavigatorBaseDirectoryTests / SidebarNavigatorFolderNavigationTests /
/// SidebarNavigatorGenerationTests の 3 スイートで重複していたものを集約した。
@MainActor
final class SidebarNavigatorStubHost: SidebarNavigatorHost {
    /// 本番同様、切替が成立したら追従する(SidebarNavigator は切替後にこの値を読む)。
    private(set) var currentFileURL: URL
    /// ファイル切替が何回起きたかの検証に使う。
    private(set) var performFileSwitchCallCount = 0
    /// 切替を失敗させたいテスト用。既定は常に成功。
    var fileSwitchOutcome: FileSwitchOutcome = .switched

    init(currentFileURL: URL) {
        self.currentFileURL = currentFileURL
    }

    func performFileSwitch(to url: URL) -> FileSwitchOutcome {
        performFileSwitchCallCount += 1
        guard case .switched = fileSwitchOutcome else { return fileSwitchOutcome }
        currentFileURL = url
        return .switched
    }

    func historyStateDidChange() {}

    /// git 状態が反映された回数。バッジの更新契機を数えるテストで使う。
    private(set) var gitStatusDidApplyCallCount = 0

    func gitStatusDidApply() {
        gitStatusDidApplyCallCount += 1
    }
}
