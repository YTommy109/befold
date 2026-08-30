import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

// 統合バーの単一入口(TASK-485.19.5)。openFind() / documentJump(_:) は
// openBar(kind:) へ収斂させ、kind の有無で既定モードの振り分けと
// 明示指定の強制を切り替える。
//
// DocumentCommandControllerTests.swift から分割した(file_length 対策)。
// 共通のフェイク(FakeDocumentRenderer)・組み立てヘルパー(makeController)は
// 元のファイルにあるものをそのまま使う。
extension DocumentCommandControllerTests {
    @Test("kind なし(⌘F相当)は、差分表示中でなければ検索を開く")
    func openBarWithoutKindOpensFindWhenNotShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer)

        controller.openBar(kind: nil)

        #expect(renderer.commands == [.openFind])
    }

    @Test("kind なし(⌘F相当)は、差分表示中なら変更ブロックジャンプを開く")
    func openBarWithoutKindOpensChangeBlockJumpWhileShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .allEnabledShowingDiffForTesting })

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
            gitDiffAvailability: .changed,
            isDirectHTMLMode: false,
            isDocumentJumpEnabled: false
        )
        let controller = makeController(renderer: renderer, capabilities: { capabilities })

        controller.openBar(kind: nil)

        #expect(renderer.commands == [.openFind])
    }

    @Test("kind を明示したときは、差分表示中でも見出しジャンプを強制する")
    func openBarWithExplicitHeadingKindIgnoresDiffDefault() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .allEnabledShowingDiffForTesting })

        controller.openBar(kind: .heading)

        #expect(renderer.commands == [.openJump(kind: .heading)])
    }

    @Test("kind を明示しても、その種類の能力が無ければ届かない(guard は openJump のまま)")
    func openBarWithExplicitChangeBlockKindStillRequiresCapability() {
        let renderer = FakeDocumentRenderer()
        // allEnabledForTesting は showsDiff 既定 false → canJumpToChangeBlock は false。
        let controller = makeController(renderer: renderer)

        controller.openBar(kind: .changeBlock)

        #expect(renderer.commands.isEmpty)
    }
}
