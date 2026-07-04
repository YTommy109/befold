import AppKit

/// 更新チェックの実行と表示ポリシーを担う。
/// 自動チェックは更新ありのときのみ、かつ同一バージョンはセッション中 1 回だけ表示する。
@MainActor
final class UpdateCheckCoordinator {
    private let updateChecker: UpdateChecker
    private let updateFlow: UpdateFlowController
    /// 自動チェックで通知済みの最新バージョン(セッション中の再通知を抑止する)。
    private var announcedVersion: String?

    init(
        updateChecker: UpdateChecker = UpdateChecker(),
        updateFlow: UpdateFlowController = UpdateFlowController()
    ) {
        self.updateChecker = updateChecker
        self.updateFlow = updateFlow
    }

    /// 更新チェックを実行し、表示ポリシーに従って結果を提示する。
    func run(userInitiated: Bool) {
        Task {
            guard !updateFlow.isRunning else { return }
            let result = await updateChecker.check(bypassCache: userInitiated)
            switch result {
            case let .updateAvailable(current, latest, downloadURL):
                if !userInitiated, latest == announcedVersion { return }
                announcedVersion = latest
                await updateFlow.run(current: current, latest: latest, downloadURL: downloadURL)
            case let .upToDate(current):
                if userInitiated { UpdateUI.presentUpToDate(current: current) }
            case .failed:
                if userInitiated { UpdateUI.presentCheckFailed() }
            }
        }
    }
}
