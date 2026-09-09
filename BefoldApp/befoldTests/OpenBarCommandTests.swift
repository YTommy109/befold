import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ⌘F の入口がどのバーを開くかの振り分け。
///
/// 境界は**種類を指定しない `openBar` の分岐**——差分表示中は変更ブロックのジャンプへ、
/// そうでなければ検索へ倒す。種類を指定したジャンプの可否は `DocumentJumpCommandTests`、
/// コマンド層の一般の方針は `DocumentCommandControllerTests` にある。
///
/// 共有のフェイクと組み立ては `DocumentCommandControllerTestSupport.swift`。
@Suite
@MainActor
struct OpenBarCommandTests {
    @Test("kind なし(⌘F相当)は、差分表示中でなければ検索を開く")
    func openBarWithoutKindOpensFindWhenNotShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer)

        controller.openBar(kind: nil)

        #expect(renderer.commands == [.openFind])
    }

    @Test("kind なし(⌘F相当)は、差分表示中なら変更ブロックジャンプを開く")
    func openBarWithoutKindOpensChangeBlockJumpWhileShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(
            renderer: renderer,
            capabilities: { .allEnabledShowingDiffForTesting }
        )

        controller.openBar(kind: nil)

        #expect(renderer.commands == [.openJump(kind: .changeBlock)])
    }

    // 責務レビューで確定した回帰(TASK-485.19.5): 既定モードの判定を
    // `showsDiff` だけで行うと、差分表示中でも文書内ジャンプの能力が無い
    // (フィーチャーゲート閉・HTML直接ロード中)場合に、openJump 側の guard で
    // 無言の no-op になり ⌘F が何も開かなくなっていた。`ViewerCapabilities.
    // defaultBarKind`(canJumpToChangeBlock 経由)を使うことでこの取りこぼしを防ぐ。
    @Test("kind なし(⌘F相当)は、差分表示中でもジャンプの能力が無ければ検索を開く(取りこぼし回帰)")
    func openBarWithoutKindFallsBackToFindWhenShowingDiffButJumpDisabled() {
        let renderer = FakeDocumentRenderer()
        let capabilities = ViewerCapabilities(
            isPresentingDocument: true,
            isRejected: false,
            isRenderable: true,
            isBinaryContent: false,
            showsCodeContent: true,
            showsDiff: true,
            supportsSourceMode: true,
            supportsDiffDisplay: true,
            supportsFind: true,
            gitDiffAvailability: .changed,
            isDirectHTMLMode: false,
            codeLanguage: nil,
            isDocumentJumpEnabled: false
        )
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { capabilities })

        controller.openBar(kind: nil)

        #expect(renderer.commands == [.openFind])
    }

    @Test("kind を明示したときは、差分表示中でも見出しジャンプを強制する")
    func openBarWithExplicitHeadingKindIgnoresDiffDefault() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(
            renderer: renderer,
            capabilities: { .allEnabledShowingDiffForTesting }
        )

        controller.openBar(kind: .heading)

        #expect(renderer.commands == [.openJump(kind: .heading)])
    }

    @Test("kind を明示しても、その種類の能力が無ければ届かない(guard は openJump のまま)")
    func openBarWithExplicitChangeBlockKindStillRequiresCapability() {
        let renderer = FakeDocumentRenderer()
        // allEnabledForTesting は showsDiff 既定 false → canJumpToChangeBlock は false。
        let controller = makeDocumentCommandController(renderer: renderer)

        controller.openBar(kind: .changeBlock)

        #expect(renderer.commands.isEmpty)
    }
}
