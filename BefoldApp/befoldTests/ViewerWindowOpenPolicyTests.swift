import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// 窓を開くときの純粋な判定(`ViewerWindowOpenPolicy.reusableController`)。
/// 候補のコントローラは実ウィンドウ付きで要るので MockedViewerWindowManager から取る
/// (判定そのものは候補を引数で受ける純関数なので、manager の状態には依らない)。
@Suite
@MainActor
struct ViewerWindowOpenPolicyTests {
    private let file = URL(fileURLWithPath: "/mock/only.md")

    /// スライド窓は再オープンの受け皿にならない(TASK-613)。`.currentTab` で候補がスライド窓だけなら
    /// nil を返し、呼び出し側は通常窓を新しく開く。
    @Test("currentTab: 候補がスライド窓だけなら再利用せず nil")
    func currentTabDoesNotReuseSlideWindow() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowOpenPolicyTests")
        defer { fixture.closeAll() }
        let slide = try #require(fixture.manager.openViewer(for: file, disposition: .slide))

        let reused = ViewerWindowOpenPolicy.reusableController(
            from: [slide], disposition: .currentTab, relativeTo: nil
        )

        #expect(reused == nil)
    }

    @Test("currentTab: スライド窓と通常窓が並んでいれば通常窓を返す")
    func currentTabPrefersViewerWindowOverSlide() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowOpenPolicyTests")
        defer { fixture.closeAll() }
        let slide = try #require(fixture.manager.openViewer(for: file, disposition: .slide))
        let viewer = try #require(fixture.manager.openViewer(for: file, disposition: .newWindow))

        let reused = ViewerWindowOpenPolicy.reusableController(
            from: [slide, viewer], disposition: .currentTab, relativeTo: nil
        )

        #expect(reused === viewer)
    }

    /// `.newTab` の重複抑止でも種別で絞る。スライド窓はタブへ合流しないので起点のグループに
    /// 居ることは無いが、判定は「候補を種別で絞ってから」の 1 箇所に置く。
    @Test("newTab: 起点のグループにスライド窓があっても候補にしない")
    func newTabDoesNotReuseSlideWindow() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowOpenPolicyTests")
        defer { fixture.closeAll() }
        let slide = try #require(fixture.manager.openViewer(for: file, disposition: .slide))

        let reused = ViewerWindowOpenPolicy.reusableController(
            from: [slide], disposition: .newTab, relativeTo: slide.window
        )

        #expect(reused == nil)
    }

    private func resolve(
        kind: ViewerWindowKind = .viewer, showSidebar: Bool? = nil, force: Bool = false, source: Bool? = nil
    ) -> Bool {
        ViewerWindowOpenPolicy.initialSidebarCollapsed(
            kind: kind, showSidebar: showSidebar, forceSidebarVisible: force,
            sourceCollapsed: source, remembered: false
        )
    }

    @Test("開閉の解決順は 種別 > CLI > フォルダー強制 > 起点の窓 > 最後の操作")
    func initialSidebarCollapsedResolutionOrder() {
        #expect(resolve(kind: .slide, showSidebar: true, force: true, source: false))
        #expect(resolve(showSidebar: false, force: true, source: false))
        #expect(!resolve(force: true, source: true))
        #expect(resolve(source: true))
        #expect(!resolve())
    }

    @Test("空タブの現在のタブへの要求は置き換えで、新しいタブや別の窓の要求は置き換えない")
    func blankTabIsReplacedOnlyByCurrentTabRequest() throws {
        let fixture = MockedViewerWindowManager(files: [], prefix: "ViewerWindowOpenPolicyBlank")
        defer { fixture.closeAll() }
        let blank = fixture.manager.blankTabs.open(relativeTo: nil)
        defer { blank.close() }
        let window = try #require(blank.window)

        #expect(ViewerWindowOpenPolicy.blankTabToReplace(.currentTab, relativeTo: window) === blank)
        #expect(ViewerWindowOpenPolicy.blankTabToReplace(.newTab, relativeTo: window) == nil)
        #expect(ViewerWindowOpenPolicy.blankTabToReplace(.newWindow, relativeTo: window) == nil)
        #expect(ViewerWindowOpenPolicy.effectiveDisposition(.currentTab, relativeTo: window) == .newTab)
        #expect(ViewerWindowOpenPolicy.tabBatchDisposition(relativeTo: window) == .currentTab)
    }

    @Test("文書の窓を起点にした現在のタブへの要求とタブの一括オープンは読み替えない")
    func documentSourceIsNotReinterpreted() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowOpenPolicyDocument")
        defer { fixture.closeAll() }
        let window = try #require(fixture.manager.openViewer(for: file)?.window)

        #expect(ViewerWindowOpenPolicy.blankTabToReplace(.currentTab, relativeTo: window) == nil)
        #expect(ViewerWindowOpenPolicy.effectiveDisposition(.currentTab, relativeTo: window) == .currentTab)
        #expect(ViewerWindowOpenPolicy.tabBatchDisposition(relativeTo: window) == .newTab)
    }
}
