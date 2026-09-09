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
/// 3 つのスイートが共有するため、ファイルスコープに置いてある。
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

    private(set) var focusSurfaceCount = 0

    func focusSurface() {
        focusSurfaceCount += 1
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

// `DocumentCommandController` を検証する 3 スイートが共有するフェイクと組み立て。
//
// **共有物をここへ出した理由（TASK-605）。** かつては
// `DocumentCommandControllerTests` の中に置き、`DocumentCommandController+JumpTests.swift`
// / `+OpenBarTests.swift` が同じ型の extension として使っていた。この形は
// `scripts/check-type-group-size.sh` の閾値を**命名だけで回避**していた——
// `Foo+Bar` を `Foo` へ畳む規則のせいで `DocumentCommandController+JumpTests` は
// キー `DocumentCommandController` になり、`DocumentCommandControllerTests` と
// 合算されなかった（実測: 分かれていれば 308 と 206、合算すれば 514 で閾値超過）。
//
// TASK-431 は「extension 方式では合算されるので負債返済にならない」と決めており、
// この 2 本はその方針が固まる前のもの。**別名の独立スイートへ**分けたうえで、
// 共有物をここへ置く（TASK-604.2 の `ViewerBridgeContractTests` と同じ形）。

/// 窓のライブ倍率の代役。onZoomChanged で流れてきた値を順に記録する。
@MainActor
final class ZoomChangeRecorder {
    var values: [Double] = []
}

/// 保存完了通知(位置・キー)を順に記録する。窓のライブ復元値の代役。
@MainActor
final class ScrollSaveRecorder {
    struct Save: Equatable {
        let position: Double
        let url: URL
        let mode: ViewerBridge.ViewMode
    }

    var saves: [Save] = []
}

/// 3 つのスイートが共有する組み立て。分離した理由はこのファイル冒頭のコメントを参照。
@MainActor
func makeDocumentCommandController(
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
        currentDocument: CurrentDocumentRef(
            store: ViewerStore(defaults: defaults), initialURL: documentCommandTestURL
        ),
        onZoomChanged: { zoomChanges.values.append($0) },
        onScrollPositionSaved: {
            scrollSaves.saves.append(ScrollSaveRecorder.Save(position: $0, url: $1, mode: $2))
        },
        capabilities: capabilities
    )
}

/// 3 スイートが対象にする文書。
let documentCommandTestURL = URL(fileURLWithPath: "/tmp/a.md")
