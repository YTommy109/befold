import AppKit
@testable import befold
import BefoldKit
import Foundation
import Testing

/// Quick Open パネルのライフサイクル、特にアプリ非アクティブ化での閉じ挙動を検証する。
/// パネルの表示自体(SwiftUI レイアウト・見た目)は対象外で、`isPresented` の遷移だけを見る。
@Suite
@MainActor
struct QuickOpenPanelControllerTests {
    /// ファイルシステムを持たない最小環境。候補は空でよい(パネルの生存だけを見るため)。
    private final class StubEnvironment: QuickOpenEnvironment {
        var baseDirectory: URL?
        var includingHiddenFiles = false

        func candidateSet() async -> QuickOpenCandidateSet {
            QuickOpenCandidateSet(candidates: [], isTruncated: false)
        }

        func directoryEntries(in _: URL) async -> [URL]? {
            []
        }

        func isDirectory(_: URL) async -> Bool {
            false
        }

        func resolveFileToOpen(at _: URL) async -> URL? {
            nil
        }
    }

    private func makeController(
        _ center: NotificationCenter,
        makeEnvironment: @escaping () -> (any QuickOpenEnvironment)? = { StubEnvironment() }
    ) -> QuickOpenPanelController {
        QuickOpenPanelController(makeEnvironment: makeEnvironment, onOpen: { _ in }, notificationCenter: center)
    }

    @Test("表示中に他アプリへ切り替えて非アクティブ化するとパネルが閉じる")
    func dismissesWhenAppResignsActive() {
        let center = NotificationCenter()
        let controller = makeController(center)

        controller.toggle()
        #expect(controller.isPresented)

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!controller.isPresented)
    }

    @Test("未表示のときに非アクティブ化してもクラッシュせず何も起きない")
    func resignActiveWhileNotPresentedIsNoop() {
        let center = NotificationCenter()
        let controller = makeController(center)

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!controller.isPresented)
    }

    @Test("閉じた後は非アクティブ化の購読が解除され、再ポストしても副作用がない")
    func unsubscribesAfterDismiss() {
        let center = NotificationCenter()
        let controller = makeController(center)

        controller.toggle()
        controller.dismiss()
        #expect(!controller.isPresented)

        // dismiss で購読解除済みのため、以降の非アクティブ化通知は何も呼ばない。
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!controller.isPresented)
    }

    @Test("環境を組み立てられない場合はパネルを開かない")
    func doesNotPresentWhenEnvironmentIsNil() {
        let center = NotificationCenter()
        let controller = makeController(center, makeEnvironment: { nil })

        controller.toggle()
        #expect(!controller.isPresented)
    }
}
