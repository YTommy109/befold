@testable import befold
import Foundation
import Testing

@MainActor
@Suite
struct CodeFontSettingsWindowControllerTests {
    private func makeController() -> CodeFontSettingsWindowController {
        let suite = "CodeFontSettingsWindowControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return CodeFontSettingsWindowController(
            preference: CodeFontPreference(defaults: defaults),
            onChange: {}
        )
    }

    @Test("未表示から toggle すると表示される")
    func togglePresentsWhenClosed() {
        let controller = makeController()
        controller.isFrontmost = { false }

        controller.toggle()

        #expect(controller.window?.isVisible == true)
        controller.window?.close()
    }

    @Test("最前面から toggle すると閉じる")
    func toggleClosesWhenFrontmost() {
        let controller = makeController()
        controller.showAndActivate()
        controller.isFrontmost = { true }

        controller.toggle()

        #expect(controller.window?.isVisible == false)
    }

    @Test("表示中だが最前面でない場合、toggle すると前面化されて閉じない")
    func toggleActivatesWhenNotFrontmost() {
        let controller = makeController()
        controller.showAndActivate()
        controller.isFrontmost = { false }

        controller.toggle()

        #expect(controller.window?.isVisible == true)
        controller.window?.close()
    }
}
