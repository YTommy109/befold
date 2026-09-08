import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 文書内ジャンプ(種類別の可否と、使える種類の同期)。
///
/// DocumentCommandControllerTests.swift から分割した(file_length 対策)。
/// 共通のフェイク(FakeDocumentRenderer)・組み立てヘルパー(makeController)は
/// 元のファイルにあるものをそのまま使う。
extension DocumentCommandControllerTests {
    @Test("文書内ジャンプは canJump が false のとき JS へ届かない")
    func documentJumpIsBlockedWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .none })

        controller.openJump(kind: .heading)

        #expect(renderer.commands.isEmpty)
    }

    @Test("文書内ジャンプは canJump が true なら種類つきで JS へ届く")
    func documentJumpReachesRendererWithCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer)

        controller.openJump(kind: .heading)

        #expect(renderer.commands == [.openJump(kind: .heading)])
    }

    @Test("変更ブロックへのジャンプは差分表示でないとき JS へ届かない")
    func changeBlockJumpIsBlockedWithoutDiff() {
        let renderer = FakeDocumentRenderer()
        // 粗い canJump は true（allEnabledForTesting は showsDiff 既定 false）。
        // 種類別の検査が無ければ、この呼び出しは素通りして 0/0 のバーが開く。
        let controller = makeController(renderer: renderer)

        controller.openJump(kind: .changeBlock)

        #expect(renderer.commands.isEmpty)
    }

    @Test("変更ブロックへのジャンプは差分表示中なら JS へ届く")
    func changeBlockJumpReachesRendererWhileShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .allEnabledShowingDiffForTesting })

        controller.openJump(kind: .changeBlock)

        #expect(renderer.commands == [.openJump(kind: .changeBlock)])
    }

    // 失効の同期(TASK-485.18)。開くときの guard と同じ canJump(to:) を通すことで、
    // 「開けるが開き続けられない」「開けないのに閉じない」という食い違いを作らない。

    @Test("使える種類の同期は差分表示中なら変更ブロックを含む")
    func jumpAvailabilityIncludesChangeBlockWhileShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .allEnabledShowingDiffForTesting })

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [.heading, .changeBlock])])
    }

    /// 差分表示でないときは変更ブロックが落ち、代わりに定義が載る
    /// （定義は差分表示中は不可なので、この 2 つは同時にはそろわない）。
    @Test("使える種類の同期は差分表示でなければ変更ブロックを含まない")
    func jumpAvailabilityExcludesChangeBlockWithoutDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer)

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [.heading, .functionDefinition])])
    }

    @Test("何もできない状態では使える種類が空になり、開いているバーは閉じる指示になる")
    func jumpAvailabilityIsEmptyWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .none })

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [])])
    }

    /// 集合が `allCases` から作られていることを固定する。種類を足したとき、
    /// 失効の同期にだけ載り忘れる形（新しい種類のバーだけ閉じない）を防ぐ。
    /// 列挙を書き足す実装に変わると、この比較が落ちる。
    ///
    /// **1 つの状態では全種類はそろわない。** 変更ブロックは差分表示中だけ、
    /// 定義は逆に差分表示でないときだけ使えるためで、条件は `ViewerCapabilities` が
    /// 持つ（TASK-485.4）。そこで差分表示中と非差分表示の和が `allCases` に
    /// 一致することをもって「全種類が検査対象になっている」ことを表す。
    /// 新しい種類がどちらの状態でも載らなければ、和に現れず落ちる。
    @Test("使える種類の同期は DocumentJumpKind の全種類を検査する")
    func jumpAvailabilityConsidersEveryKind() {
        let showingDiff = syncedKinds(for: .allEnabledShowingDiffForTesting)
        let notShowingDiff = syncedKinds(for: .allEnabledForTesting)

        #expect(showingDiff.union(notShowingDiff) == Set(DocumentJumpKind.allCases))
    }

    /// その能力の状態で viewer へ同期される種類の集合。
    private func syncedKinds(for capabilities: ViewerCapabilities) -> Set<DocumentJumpKind> {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { capabilities })

        controller.syncJumpAvailability()

        return renderer.commands.reduce(into: Set<DocumentJumpKind>()) { result, command in
            guard case let .applyJumpAvailability(kinds) = command else { return }
            result.formUnion(kinds)
        }
    }
}
