@testable import befold
import Foundation

/// SidebarNavigator の unit テストが共通で使うダミー host。
/// SidebarNavigatorHost は befold 内部 protocol のため BefoldTestSupport には置けない。
/// SidebarNavigatorBaseDirectoryTests / SidebarNavigatorFolderNavigationTests /
/// SidebarNavigatorGenerationTests の 3 スイートで重複していたものを集約した。
@MainActor
final class SidebarNavigatorStubHost: SidebarNavigatorHost {
    let currentFileURL: URL
    /// navigateToFolder がファイル切替を一切行わないはずのケースの検証に使う。
    private(set) var performFileSwitchCallCount = 0

    init(currentFileURL: URL) {
        self.currentFileURL = currentFileURL
    }

    func performFileSwitch(to _: URL) -> FileSwitchOutcome {
        performFileSwitchCallCount += 1
        return .switched
    }

    func historyStateDidChange() {}
}
