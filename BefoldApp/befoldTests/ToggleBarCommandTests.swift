import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ⌘F / ⇧⌘F の入口がどのバーをトグルするかの振り分け(TASK-485.28)。
///
/// 境界は**表示ごとの種類の選択**——⌘F は表示に依らず検索、⇧⌘F はその表示で使える
/// ジャンプ(見出し・定義・変更箇所は排他で高々 1 つ)を、無ければ検索を選ぶ。
/// 開いていれば閉じる判定は面の側(web 面は JS の bar.ts、PDF 面は `PDFFindModel`)が
/// 持つので、ここでは「どの種類を面へ渡すか」だけを見る。
///
/// 共有のフェイクと組み立ては `DocumentCommandControllerTestSupport.swift`。
@Suite
@MainActor
struct ToggleBarCommandTests {
    @Test("⌘F は差分表示中でも検索をトグルする")
    func toggleFindAlwaysTargetsSearch() {
        for capabilities in [ViewerCapabilities.allEnabledForTesting, .allEnabledShowingDiffForTesting] {
            let renderer = FakeDocumentRenderer()
            let controller = makeDocumentCommandController(renderer: renderer, capabilities: { capabilities })

            controller.toggleFind()

            #expect(renderer.commands == [.toggleFind])
        }
    }

    @Test("⇧⌘F は表示で使える種類のジャンプをトグルする")
    func toggleJumpTargetsTheAvailableKind() {
        let cases: [(ViewerCapabilities, DocumentJumpKind)] = [
            (.allEnabledWithoutCodeLanguageForTesting, .heading),
            (.allEnabledForTesting, .functionDefinition),
            (.allEnabledShowingDiffForTesting, .changeBlock),
        ]
        for (capabilities, kind) in cases {
            let renderer = FakeDocumentRenderer()
            let controller = makeDocumentCommandController(renderer: renderer, capabilities: { capabilities })

            controller.toggleJump()

            #expect(renderer.commands == [.toggleJump(kind: kind)])
        }
    }

    @Test("⇧⌘F は使えるジャンプが無い表示では検索をトグルする")
    func toggleJumpFallsBackToFindWithoutJumpKind() {
        let renderer = FakeDocumentRenderer()
        // mmd・JSON・未対応言語など: 見出しも定義も持たず、差分表示でもない。
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: {
            makeCapabilities(showsDiff: false, supportsHeadingJump: false, isDocumentJumpEnabled: true)
        })

        controller.toggleJump()

        #expect(renderer.commands == [.toggleFind])
    }

    /// 旧 openBar の回帰(TASK-485.19.5)の形を引き継ぐ: ジャンプの能力が無い
    /// (フィーチャーゲート閉・HTML 直接ロード中)ときに無言の no-op にしない。
    @Test("⇧⌘F は差分表示中でもジャンプの能力が無ければ検索をトグルする")
    func toggleJumpFallsBackToFindWhenJumpDisabled() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: {
            makeCapabilities(showsDiff: true, supportsHeadingJump: true, isDocumentJumpEnabled: false)
        })

        controller.toggleJump()

        #expect(renderer.commands == [.toggleFind])
    }

    @Test("何もできない状態では ⌘F も ⇧⌘F も面へ届かない")
    func nothingReachesRendererWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { .none })

        controller.toggleFind()
        controller.toggleJump()

        #expect(renderer.commands.isEmpty)
    }

    private func makeCapabilities(
        showsDiff: Bool, supportsHeadingJump: Bool, isDocumentJumpEnabled: Bool
    ) -> ViewerCapabilities {
        ViewerCapabilities(
            isPresentingDocument: true,
            isRejected: false,
            isRenderable: true,
            isBinaryContent: false,
            showsCodeContent: true,
            showsDiff: showsDiff,
            supportsSourceMode: true,
            supportsDiffDisplay: true,
            supportsFind: true,
            gitDiffAvailability: .changed,
            isDirectHTMLMode: false,
            supportsHeadingJump: supportsHeadingJump,
            codeLanguage: nil,
            isDocumentJumpEnabled: isDocumentJumpEnabled
        )
    }
}
