@testable import befold
import Testing

/// 絞り込みの窓ごと状態。永続化しないので UserDefaults は触らない。
@MainActor
@Suite
struct SidebarTransientStateTests {
    private func makeModel() -> SidebarTransientState {
        SidebarTransientState()
    }

    @Test("既定では絞り込み欄は閉じている")
    func defaultsToClosedFilter() {
        let model = makeModel()

        #expect(!model.isFilterActive)
        #expect(model.filterText.isEmpty)
    }

    @Test("closeFilter は欄を閉じ、絞り込み文字列も消す")
    func closeFilterClearsText() {
        let model = makeModel()
        model.isFilterActive = true
        model.filterText = "readme"

        model.closeFilter()

        #expect(!model.isFilterActive)
        #expect(model.filterText.isEmpty)
    }
}
