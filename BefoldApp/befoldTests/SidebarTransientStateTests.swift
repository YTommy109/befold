@testable import befold
import Testing

/// 絞り込みとスライドモードの窓ごと状態。永続化しないので UserDefaults は触らない。
@MainActor
@Suite
struct SidebarTransientStateTests {
    private func makeModel() -> SidebarTransientState {
        SidebarTransientState()
    }

    @Test("既定ではスライドモードではない")
    func defaultsToOff() {
        #expect(!makeModel().isSlideMode)
    }

    @Test("スライドモードに入るとフィルターが閉じ、絞り込み文字列も消える")
    func enteringClosesFilter() {
        let model = makeModel()
        model.isFilterActive = true
        model.filterText = "readme"

        model.setSlideMode(true)

        #expect(model.isSlideMode)
        #expect(!model.isFilterActive)
        #expect(model.filterText.isEmpty)
    }

    @Test("スライドモードを抜けてもフィルターは開き直さない")
    func leavingDoesNotReopenFilter() {
        let model = makeModel()
        model.isFilterActive = true
        model.filterText = "readme"
        model.setSlideMode(true)

        model.setSlideMode(false)

        #expect(!model.isSlideMode)
        #expect(!model.isFilterActive)
        #expect(model.filterText.isEmpty)
    }
}
