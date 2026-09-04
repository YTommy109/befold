@testable import befold
import Foundation
import Testing

/// サイドバーを畳んだらスライドモードが残らないこと。
/// 残ると、次に開いたときアイコン幅のまま戻り、ヘッダーの解除ボタンにしか出口が無くなる。
@MainActor
@Suite
struct SlideModeCollapseExitTests {
    private func makeModel() -> FileListModel {
        FileListModel(
            currentDirectory: URL(fileURLWithPath: "/tmp/slide-mode-collapse", isDirectory: true),
            entries: [], selection: nil
        )
    }

    @Test("サイドバーを畳むとスライドモードが解除される")
    func collapsingLeavesSlideMode() {
        let model = makeModel()
        model.setSlideMode(true)

        SlideModeExitOnHide.apply(to: model)

        #expect(!model.isSlideMode)
    }

    @Test("スライドモードでないときに畳んでも何も起きない")
    func collapsingOutsideSlideModeIsHarmless() {
        let model = makeModel()

        SlideModeExitOnHide.apply(to: model)

        #expect(!model.isSlideMode)
    }
}
