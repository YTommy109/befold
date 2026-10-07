import AppKit
@testable import befold
import SwiftUI
import Testing

/// サイドバー開閉のアニメーションを、画面に出ていない窓で省くことの担保(TASK-673)。
///
/// 守りたい保証は「出ていない窓の開閉で、AppKit のアニメーション用ワーカースレッドを
/// 塞いだまま残さない」こと。スレッドの残存はテストプロセス内で安定して数えられない
/// (並列に走る他のテストがスレッドを増減させる)ため、ここでは**開閉の経路を決める判定**を測る。
/// この判定が `toggleSidebar(_:)` の唯一の分岐なので、判定を外すとこのテストが落ちる。
@MainActor
struct ViewerSplitViewControllerAnimationTests {
    private typealias Controller = ViewerSplitViewController<EmptyView, EmptyView>

    /// 実際に画面へ出さずに「見えている窓」を作る。
    private final class VisibleWindow: NSWindow {
        override var isVisible: Bool {
            true
        }
    }

    @Test("画面に出ていない窓ではアニメーションさせない")
    func hiddenWindowDoesNotAnimate() {
        let window = NSWindow()
        #expect(!window.isVisible)

        #expect(!Controller.shouldAnimateSidebarToggle(in: window))
    }

    @Test("画面に出ている窓では従来どおりアニメーションさせる")
    func visibleWindowAnimates() {
        #expect(Controller.shouldAnimateSidebarToggle(in: VisibleWindow()))
    }

    @Test("窓へ載っていないコントローラは従来どおり AppKit に任せる")
    func noWindowKeepsAppKitBehavior() {
        #expect(Controller.shouldAnimateSidebarToggle(in: nil))
    }
}
