import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// レンダラへ「何が命じられたか」を fake で受け取り、コマンド層の方針
/// (能力による可否・結果の保存先)を検証する(ADR 0002 段 4)。
/// port を切る前は WebView 不在で全コマンドが無言の no-op になり、
/// 命令が届いたかどうかをテストで区別できなかった。
///
/// `private` ではなく型内部可視性(既定の internal)にしてあるのは、
/// `DocumentCommandController+OpenBarTests.swift` からも使うため
/// (file_length 対策の分割。Swift の `private` はファイルスコープなので
/// 分割先から見えなくなる)。
@MainActor
final class FakeDocumentRenderer: DocumentRendering {
    enum Command: Equatable {
        case applyZoom(Double)
        case applyCodeFont(family: String?, points: Double?)
        case applyCsvNumberFormat(grouping: Bool, negativeStyle: CsvNegativeStyle)
        case changeZoom(ZoomChange)
        case openFind
        case findNext
        case findPrevious
        case openJump(kind: DocumentJumpKind)
        case applyJumpAvailability(kinds: Set<DocumentJumpKind>)
        case print
        case currentScrollPosition
        case rotate(degrees: Int)
        case noteRename(old: URL, new: URL)
    }

    private(set) var commands: [Command] = []
    var isDirectHTMLMode = false
    /// changeZoom の戻り値。直接 HTML モードの適用後倍率を模す。
    var zoomAfterChange: Double?
    /// currentScrollPosition が返す値。nil なら completion を呼ばない。
    var scrollPosition: Double?

    /// いまの回転角。`rotate` が積み上げる。
    private(set) var currentRotation = 0

    func applyZoom(_ zoom: Double) {
        commands.append(.applyZoom(zoom))
    }

    func rotate(byDegrees degrees: Int) {
        commands.append(.rotate(degrees: degrees))
        currentRotation += degrees
    }

    func applyCodeFont(family: String?, points: Double?) {
        commands.append(.applyCodeFont(family: family, points: points))
    }

    func applyCsvNumberFormat(grouping: Bool, negativeStyle: CsvNegativeStyle) {
        commands.append(.applyCsvNumberFormat(grouping: grouping, negativeStyle: negativeStyle))
    }

    func changeZoom(_ change: ZoomChange) -> Double? {
        commands.append(.changeZoom(change))
        return zoomAfterChange
    }

    func openFind() {
        commands.append(.openFind)
    }

    func findNext() {
        commands.append(.findNext)
    }

    func findPrevious() {
        commands.append(.findPrevious)
    }

    func openJump(kind: DocumentJumpKind) {
        commands.append(.openJump(kind: kind))
    }

    func applyJumpAvailability(_ kinds: Set<DocumentJumpKind>) {
        commands.append(.applyJumpAvailability(kinds: kinds))
    }

    func printDocument(over _: NSWindow?) {
        commands.append(.print)
    }

    func currentScrollPosition(_ completion: @escaping (Double) -> Void) {
        commands.append(.currentScrollPosition)
        guard let scrollPosition else { return }
        completion(scrollPosition)
    }

    func noteRename(from oldURL: URL, to newURL: URL) {
        commands.append(.noteRename(old: oldURL, new: newURL))
    }
}

extension ZoomChange: @retroactive Equatable {}

@Suite
@MainActor
struct DocumentCommandControllerTests {
    private let url = URL(fileURLWithPath: "/tmp/a.md")

    /// 窓のライブ倍率の代役。onZoomChanged で流れてきた値を順に記録する。
    /// `makeController` のデフォルト引数の型として使われるため、`private` には
    /// できない(型内部可視性のメソッドは private 型を引数に取れない)。
    final class ZoomChangeRecorder {
        var values: [Double] = []
    }

    /// 保存完了通知(位置・キー)を順に記録する。窓のライブ復元値の代役。
    final class ScrollSaveRecorder {
        struct Save: Equatable {
            let position: Double
            let url: URL
            let mode: ViewerBridge.ViewMode
        }

        var saves: [Save] = []
    }

    /// `private` ではなく内部可視性にしてあるのは、`DocumentCommandController+
    /// OpenBarTests.swift`(file_length 対策の分割先)からも呼ぶため。
    func makeController(
        renderer: FakeDocumentRenderer,
        perFileState: PerFileStateStore? = nil,
        zoomChanges: ZoomChangeRecorder = ZoomChangeRecorder(),
        scrollSaves: ScrollSaveRecorder = ScrollSaveRecorder(),
        capabilities: @escaping () -> ViewerCapabilities = { .allEnabledForTesting }
    ) -> DocumentCommandController {
        let defaults = makeIsolatedDefaults(prefix: "DocumentCommandControllerTests")
        return DocumentCommandController(
            // 面の束ごしに差し込む。宛先の決定は DocumentSurfaces が持つので、
            // ここでフェイクを直接コマンド側へ渡す形は取らない(TASK-564.6)。
            surfaces: DocumentSurfaces(
                webRenderer: renderer,
                findOptions: FindOptionsPreference(defaults: defaults)
            ),
            perFileState: perFileState ?? PerFileStateStore(defaults: defaults),
            currentDocument: CurrentDocumentRef(store: ViewerStore(defaults: defaults), initialURL: url),
            onZoomChanged: { zoomChanges.values.append($0) },
            onScrollPositionSaved: {
                scrollSaves.saves.append(ScrollSaveRecorder.Save(position: $0, url: $1, mode: $2))
            },
            capabilities: capabilities
        )
    }

    @Test("能力が無ければ、ユーザー操作はレンダラへ届かない")
    func blocksDocumentCommandsWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .none })

        controller.zoomIn()
        controller.zoomOut()
        controller.resetZoom()
        controller.openFind()
        controller.findNext()
        controller.findPrevious()
        controller.printDocument(over: nil)

        #expect(renderer.commands.isEmpty)
    }

    @Test("能力があれば、対応する命令がレンダラへ届く")
    func forwardsCommandsWhenCapable() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer)

        controller.zoomIn()
        controller.zoomOut()
        controller.resetZoom()
        controller.openFind()
        controller.findNext()
        controller.findPrevious()
        controller.printDocument(over: nil)

        #expect(renderer.commands == [
            .changeZoom(.zoomIn), .changeZoom(.zoomOut), .changeZoom(.reset),
            .openFind, .findNext, .findPrevious, .print,
        ])
    }

    @Test("設定の反映は能力で止めない(フォルダー表示中の設定変更を取り残さない)")
    func settingsAreAppliedRegardlessOfCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .none })

        controller.applyCodeFont(family: "Menlo", points: 12)

        #expect(renderer.commands == [.applyCodeFont(family: "Menlo", points: 12)])
    }

    /// 数値表示の反映もフォントと同じく能力(ViewerCapabilities)では止めない。
    /// 止めると、フォルダーを見ている間に設定を変えた窓だけ古い表示のまま残る。
    @Test("数値表示の設定は能力に関わらず WebView へ届く")
    func appliesCsvNumberFormatRegardlessOfCapabilities() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .none })

        controller.applyCsvNumberFormat(grouping: false, negativeStyle: .triangleRed)

        #expect(
            renderer.commands == [.applyCsvNumberFormat(grouping: false, negativeStyle: .triangleRed)]
        )
    }

    @Test("直接 HTML モードで返った倍率だけを、窓のライブ値と保存値の両方へ反映する")
    func persistsZoomReturnedByRenderer() {
        let renderer = FakeDocumentRenderer()
        let defaults = makeIsolatedDefaults(prefix: "DocumentCommandControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let zoomChanges = ZoomChangeRecorder()
        let controller = makeController(
            renderer: renderer, perFileState: perFileState, zoomChanges: zoomChanges
        )

        // viewer.js が倍率を持つ通常モードでは nil が返り、保存も通知も JS からの経路に任せる
        renderer.zoomAfterChange = nil
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: url) == ZoomStore.defaultZoom)
        #expect(zoomChanges.values.isEmpty)

        // 直接 HTML モードでは適用後の倍率が返る。viewer.js からの通知が来ない経路なので、
        // ここで窓のライブ値も更新しないと画面と食い違ったまま取り残される。
        renderer.zoomAfterChange = 1.25
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: url) == 1.25)
        #expect(zoomChanges.values == [1.25])
    }

    /// 位置を記憶するのは窓側(`ViewerDocumentPresenter`)なので、ここは「取得できたときだけ
    /// キーごと通知する」ところまでを見る。
    @Test("スクロール位置は、取得できた場合だけ指定キーごと通知する")
    func reportsScrollPositionOnlyWhenAvailable() {
        let renderer = FakeDocumentRenderer()
        let scrollSaves = ScrollSaveRecorder()
        let controller = makeController(renderer: renderer, scrollSaves: scrollSaves)

        renderer.scrollPosition = nil
        controller.saveCurrentScrollPosition(for: url, mode: .rendered)
        #expect(scrollSaves.saves.isEmpty)

        renderer.scrollPosition = 42
        controller.saveCurrentScrollPosition(for: url, mode: .rendered)
        #expect(scrollSaves.saves == [ScrollSaveRecorder.Save(position: 42, url: url, mode: .rendered)])
    }

    /// 取得完了は「そのキーと値」ごと窓へ伝える。窓はこれで記憶とライブな復元値を
    /// 追いつかせるため、値を渡さず通知だけにすると窓が読み直す形になってしまう
    /// (ADR 0002 / TASK-394)。
    @Test("保存が完了したら、保存したキーと値を窓へ伝える")
    func reportsSavedScrollPositionWithItsKey() {
        let renderer = FakeDocumentRenderer()
        let scrollSaves = ScrollSaveRecorder()
        let controller = makeController(renderer: renderer, scrollSaves: scrollSaves)

        // 取得できなければ保存も通知もしない
        renderer.scrollPosition = nil
        controller.saveCurrentScrollPosition(for: url, mode: .rendered)
        #expect(scrollSaves.saves.isEmpty)

        renderer.scrollPosition = 42
        controller.saveCurrentScrollPosition(for: url, mode: .source)

        #expect(scrollSaves.saves.count == 1)
        #expect(scrollSaves.saves.first?.position == 42)
        #expect(scrollSaves.saves.first?.url == url)
        #expect(scrollSaves.saves.first?.mode == .source)
    }

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

    // 統合バーの単一入口(TASK-485.19.5)のテストは
    // DocumentCommandController+OpenBarTests.swift へ分割した(file_length 対策)。

    // 失効の同期(TASK-485.18)。開くときの guard と同じ canJump(to:) を通すことで、
    // 「開けるが開き続けられない」「開けないのに閉じない」という食い違いを作らない。

    @Test("使える種類の同期は差分表示中なら変更ブロックを含む")
    func jumpAvailabilityIncludesChangeBlockWhileShowingDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .allEnabledShowingDiffForTesting })

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [.heading, .changeBlock])])
    }

    @Test("使える種類の同期は差分表示でなければ変更ブロックを含まない")
    func jumpAvailabilityExcludesChangeBlockWithoutDiff() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer)

        controller.syncJumpAvailability()

        #expect(renderer.commands == [.applyJumpAvailability(kinds: [.heading])])
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
    @Test("使える種類の同期は DocumentJumpKind の全種類を検査する")
    func jumpAvailabilityConsidersEveryKind() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .allEnabledShowingDiffForTesting })

        controller.syncJumpAvailability()

        let synced = renderer.commands.compactMap { command -> Set<DocumentJumpKind>? in
            guard case let .applyJumpAvailability(kinds) = command else { return nil }
            return kinds
        }
        #expect(synced == [Set(DocumentJumpKind.allCases)])
    }

    @Test("rename の追随は状態の反映なので能力で止めない")
    func noteRenameIsForwardedRegardlessOfCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .none })
        let renamed = URL(fileURLWithPath: "/tmp/b.md")

        controller.noteRename(from: url, to: renamed)

        #expect(renderer.commands == [.noteRename(old: url, new: renamed)])
    }

    @Test("isDirectHTMLMode はレンダラの値をそのまま反映する")
    func isDirectHTMLModeReflectsRenderer() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer)
        #expect(!controller.isDirectHTMLMode)

        renderer.isDirectHTMLMode = true
        #expect(controller.isDirectHTMLMode)
    }
}
