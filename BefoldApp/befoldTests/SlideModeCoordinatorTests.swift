@testable import befold
import Foundation
import Testing

/// スライドモードの出入りの協調手順。
/// 「畳んだら解除される」は、残るとアイコン幅のまま次に開いてしまうため落とせない。
@MainActor
@Suite
struct SlideModeCoordinatorTests {
    /// 幅の適用先。真偽値を持たない契約（真値は FileListModel）を破っていないかも見る。
    private final class CollapsibleSpy: SidebarCollapsible {
        var isSidebarCollapsed = false
        private(set) var slideModeCalls: [Bool] = []

        func setSidebarCollapsed(_ collapsed: Bool) {
            isSidebarCollapsed = collapsed
        }

        func setSlideMode(_ enabled: Bool) {
            slideModeCalls.append(enabled)
        }
    }

    private func makeModel() -> FileListModel {
        FileListModel(
            currentDirectory: URL(fileURLWithPath: "/tmp/slide-mode-coordinator", isDirectory: true),
            entries: [], selection: nil
        )
    }

    @Test("トグルで状態と幅が同時に切り替わる")
    func toggleUpdatesStateAndWidth() {
        let model = makeModel()
        let collapsible = CollapsibleSpy()

        SlideModeCoordinator.toggle(model: model, collapsible: collapsible)
        #expect(model.transient.isSlideMode)
        #expect(collapsible.slideModeCalls == [true])

        SlideModeCoordinator.toggle(model: model, collapsible: collapsible)
        #expect(!model.transient.isSlideMode)
        #expect(collapsible.slideModeCalls == [true, false])
    }

    @Test("サイドバーを畳むとスライドモードが解除され、幅も戻される")
    func collapsingLeavesSlideMode() {
        let model = makeModel()
        let collapsible = CollapsibleSpy()
        SlideModeCoordinator.setEnabled(true, model: model, collapsible: collapsible)

        SlideModeCoordinator.setEnabled(false, model: model, collapsible: collapsible)

        #expect(!model.transient.isSlideMode)
        #expect(collapsible.slideModeCalls == [true, false])
    }

    @Test("同じ値の設定では幅に触らない")
    func settingSameValueIsNoop() {
        let model = makeModel()
        let collapsible = CollapsibleSpy()

        SlideModeCoordinator.setEnabled(false, model: model, collapsible: collapsible)

        #expect(!model.transient.isSlideMode)
        #expect(collapsible.slideModeCalls.isEmpty)
    }
}
