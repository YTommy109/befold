import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 文書内ジャンプ(種類別の可否と、使える種類の同期)。
///
/// 境界は**種類ごとの可否**——`canJump` の粗い判定だけでは通ってしまう
/// 「差分表示でないのに変更ブロックへ跳ぶ」形をここで止める。倍率・スクロール・印刷など
/// コマンド層の一般の方針は `DocumentCommandControllerTests`、⌘F の入口の振り分けは
/// `OpenBarCommandTests` にある。
///
/// 共有のフェイクと組み立ては `DocumentCommandControllerTestSupport.swift`。
@Suite
@MainActor
struct DocumentJumpCommandTests {
    @Test("文書内ジャンプは canJump が false のとき JS へ届かない")
    func documentJumpIsBlockedWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { .none })

        controller.openJump(kind: .heading)

        #expect(renderer.commands.isEmpty)
    }

    @Test("文書内ジャンプは canJump が true なら種類つきで JS へ届く")
    func documentJumpReachesRendererWithCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer)

        controller.openJump(kind: .functionDefinition)

        #expect(renderer.commands == [.openJump(kind: .functionDefinition)])
    }

    @Test("変更ブロックへのジャンプは差分表示でないとき JS へ届かない")
    func changeBlockJumpIsBlockedWithoutDiff() {
        let renderer = FakeDocumentRenderer()
        // 粗い canJump は true（allEnabledForTesting は showsDiff 既定 false）。
        // 種類別の検査が無ければ、この呼び出しは素通りして 0/0 のバーが開く。
        let controller = makeDocumentCommandController(renderer: renderer)

        controller.openJump(kind: .changeBlock)

        #expect(renderer.commands.isEmpty)
    }

    @Test("変更ブロックへのジャンプは差分表示中なら JS へ届く")
    func changeBlockJumpReachesRendererWhileShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(
            renderer: renderer,
            capabilities: { .allEnabledShowingDiffForTesting }
        )

        controller.openJump(kind: .changeBlock)

        #expect(renderer.commands == [.openJump(kind: .changeBlock)])
    }

    // 失効の同期(TASK-485.18)。開くときの guard と同じ canJump(to:) を通すことで、
    // 「開けるが開き続けられない」「開けないのに閉じない」という食い違いを作らない。

    @Test("使える種類の同期は差分表示中なら変更ブロックを含む")
    func jumpAvailabilityIncludesChangeBlockWhileShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(
            renderer: renderer,
            capabilities: { .allEnabledShowingDiffForTesting }
        )

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [.changeBlock])])
    }

    /// 差分表示でないときは変更ブロックが落ち、代わりに定義が載る
    /// （見出し・定義・変更ブロックは排他で、同時には 1 つしか載らない / TASK-485.26）。
    @Test("使える種類の同期は差分表示でなければ変更ブロックを含まない")
    func jumpAvailabilityExcludesChangeBlockWithoutDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer)

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [.functionDefinition])])
    }

    @Test("何もできない状態では使える種類が空になり、開いているバーは閉じる指示になる")
    func jumpAvailabilityIsEmptyWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { .none })

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [])])
    }

    /// 集合が `allCases` から作られていることを固定する。種類を足したとき、
    /// 失効の同期にだけ載り忘れる形（新しい種類のバーだけ閉じない）を防ぐ。
    /// 列挙を書き足す実装に変わると、この比較が落ちる。
    ///
    /// **1 つの状態では全種類はそろわない。** 見出し・定義・変更ブロックは排他で
    /// （TASK-485.26）、条件は `ViewerCapabilities` が持つ。そこで差分表示中・
    /// 対応言語のソース表示・言語なしの 3 状態の和が `allCases` に一致することをもって
    /// 「全種類が検査対象になっている」ことを表す。
    /// 新しい種類がどの状態でも載らなければ、和に現れず落ちる。
    @Test("使える種類の同期は DocumentJumpKind の全種類を検査する")
    func jumpAvailabilityConsidersEveryKind() {
        let showingDiff = syncedKinds(for: .allEnabledShowingDiffForTesting)
        let showingCode = syncedKinds(for: .allEnabledForTesting)
        let withoutLanguage = syncedKinds(for: .allEnabledWithoutCodeLanguageForTesting)

        #expect(showingDiff.union(showingCode).union(withoutLanguage) == Set(DocumentJumpKind.allCases))
    }

    /// その能力の状態で viewer へ同期される種類の集合。
    private func syncedKinds(for capabilities: ViewerCapabilities) -> Set<DocumentJumpKind> {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { capabilities })

        controller.syncJumpAvailability()

        return renderer.commands.reduce(into: Set<DocumentJumpKind>()) { result, command in
            guard case let .applyJumpAvailability(kinds) = command else { return }
            result.formUnion(kinds)
        }
    }
}
