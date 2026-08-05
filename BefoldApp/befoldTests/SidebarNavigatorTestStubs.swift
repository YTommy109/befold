@testable import befold
import Foundation

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
}
