import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 命令の**宛先**が「1 枚へ振り分ける操作」と「全部へ配る追随」に分かれていることを固定する
/// (TASK-564.6)。
///
/// **面が 1 枚しか無いうちは、呼び出しの回数を数えても差が出ない。** 配っても
/// 振り分けても同じ 1 枚に届くため、「配るべきものを振り分けてしまった」実装でも
/// 回数のテストは通ってしまう。PDF の面が入る TASK-564.1 まで待つと、そのときには
/// 既に間違った形が書かれている。
///
/// そこで**宛先の書き方そのものを走査して固定する**。追随の 4 つが
/// `surfaces.syncingAll` を回っていること、操作側が回っていないことを見る。
/// 面の枚数に依らないので、いま 1 枚でも意味を持つ。
///
/// 振り分けてはならない理由は `DocumentSurfaceSyncing` の doc にある
/// (設定の取り残しと、対応形式が変わるリネームでの追随漏れ = TASK-401 / TASK-393)。
@MainActor
@Suite
struct DocumentSurfaceDispatchTests {
    /// 何を受けたかだけを数える面。
    private final class RecordingSurface: DocumentRendering {
        var codeFontCalls = 0
        var csvFormatCalls = 0
        var jumpAvailabilityCalls = 0
        var renameCalls: [(URL, URL)] = []
        var findCalls = 0
        var printCalls = 0
        var zoomCalls = 0

        var isDirectHTMLMode = false

        func applyZoom(_: Double) {}

        func changeZoom(_: ZoomChange) -> Double? {
            zoomCalls += 1
            return nil
        }

        func openFind() {
            findCalls += 1
        }

        func findNext() {}
        func findPrevious() {}
        func openJump(kind _: DocumentJumpKind) {}
        func printDocument(over _: NSWindow?) {
            printCalls += 1
        }

        func currentScrollPosition(_: @escaping (Double) -> Void) {}

        func applyCodeFont(family _: String?, points _: Double?) {
            codeFontCalls += 1
        }

        func applyCsvNumberFormat(grouping _: Bool, negativeStyle _: CsvNegativeStyle) {
            csvFormatCalls += 1
        }

        func applyJumpAvailability(_: Set<DocumentJumpKind>) {
            jumpAvailabilityCalls += 1
        }

        func noteRename(from oldURL: URL, to newURL: URL) {
            renameCalls.append((oldURL, newURL))
        }
    }

    /// `DocumentSurfaces` は面が 1 枚のうちは束が 1 要素。
    /// 「配る」側の宛先が束そのものであることを、まずここで押さえる。
    @Test("配る側の宛先は束に入っている面すべてである")
    func syncingTargetsEverySurfaceInTheBundle() {
        let surface = RecordingSurface()
        let surfaces = DocumentSurfaces(webRenderer: surface)

        #expect(surfaces.syncingAll.count == 1)
        #expect(surfaces.syncingAll.first === surface)
    }

    /// 「1 枚へ振り分ける」側は、束から 1 つだけを返す。
    /// 面が 1 枚のうちは種別に関係なく同じ面が返る。
    @Test("振り分ける側は種別に対して面を 1 つ返す")
    func operatingReturnsASingleSurface() {
        let surface = RecordingSurface()
        let surfaces = DocumentSurfaces(webRenderer: surface)

        #expect(surfaces.operating(on: .markdown) === surface)
        #expect(surfaces.operating(on: .pdf) === surface)
    }

    /// 設定の反映とリネーム追随が、束の全要素へ配られること。
    /// 実装が `operating(on:)` で 1 枚に絞る形へ変わると、束を 2 要素にしたときに
    /// 片方の数が 0 のままになって落ちる。
    @Test("設定の反映とリネームは束の全要素へ届く")
    func syncingReachesEverySurface() {
        let surface = RecordingSurface()
        let controller = Self.makeController(surface: surface)
        let old = URL(fileURLWithPath: "/mock/a.md")
        let new = URL(fileURLWithPath: "/mock/b.md")

        controller.applyCodeFont(family: "Menlo", points: 12)
        controller.applyCsvNumberFormat(grouping: true, negativeStyle: .plain)
        controller.syncJumpAvailability()
        controller.noteRename(from: old, to: new)

        #expect(surface.codeFontCalls == 1)
        #expect(surface.csvFormatCalls == 1)
        #expect(surface.jumpAvailabilityCalls == 1)
        #expect(surface.renameCalls.count == 1)
    }

    /// 追随の 4 つが束を回っていること。**面が 1 枚のうちは回数では差が出ない**ので、
    /// 宛先の書き方をソースで固定する(このファイル冒頭の doc を参照)。
    /// `syncingAll` を回るのをやめて 1 枚へ送る実装に変えると、ここで落ちる。
    @Test("追随の実装は束を回っている")
    func syncingImplementationIteratesTheBundle() throws {
        let source = try Self.commandControllerSource()
        for method in ["applyCodeFont", "applyCsvNumberFormat", "syncJumpAvailability", "noteRename"] {
            let body = try #require(Self.methodBody(named: method, in: source), "\(method) が見つからない")
            #expect(
                body.contains("surfaces.syncingAll"),
                "\(method) が束を回っていない(1 枚へ振り分けている): \(body)"
            )
        }
    }

    /// 操作側は束を回らないこと。全部へ配ると、見えていない面まで印刷やズームに反応する。
    @Test("操作の実装は束を回らない")
    func operationImplementationDoesNotIterateTheBundle() throws {
        let source = try Self.commandControllerSource()
        for method in ["printDocument", "openFind", "findNext", "findPrevious", "openJump"] {
            let body = try #require(Self.methodBody(named: method, in: source), "\(method) が見つからない")
            #expect(
                !body.contains("surfaces.syncingAll"),
                "\(method) が束を回っている(全部へ配っている): \(body)"
            )
        }
    }

    private static func commandControllerSource() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests
            .deletingLastPathComponent() // BefoldApp
            .appendingPathComponent("befold/App/WebViewCommandController.swift")
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// `func <name>` の行から、インデントが戻るまでの本文を返す。
    /// 宛先の書き方だけを見たいので、簡易な走査で足りる。
    private static func methodBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else { return nil }
        var body: [String] = []
        for line in lines[start...].dropFirst() {
            if line.hasPrefix("    }") { break }
            body.append(line)
        }
        return body.joined(separator: "\n")
    }

    /// ユーザー操作は束へ配らず、`operating(on:)` が返した 1 枚だけへ届くこと。
    @Test("ユーザー操作は振り分けた 1 枚だけへ届く")
    func operationsReachOnlyTheActiveSurface() {
        let surface = RecordingSurface()
        let controller = Self.makeController(surface: surface)

        controller.zoomIn()
        controller.openFind()
        controller.printDocument(over: nil)

        #expect(surface.zoomCalls == 1)
        #expect(surface.findCalls == 1)
        #expect(surface.printCalls == 1)
    }

    /// 宛先の決定が**描画の確定した種別**を見ていること。
    /// 提示予定の URL（`CurrentDocumentRef.url`）から導くと、切替直後に
    /// 画面と宛先がずれる（`DocumentSurfaces.operating(on:)` の doc）。
    @Test("宛先は提示予定の URL ではなく描画が確定した種別から決まる")
    func dispatchUsesRenderedFileTypeNotPendingURL() {
        let defaults = makeIsolatedDefaults(prefix: "DocumentSurfaceDispatchTests")
        let store = ViewerStore(defaults: defaults)
        let ref = CurrentDocumentRef(store: store, initialURL: URL(fileURLWithPath: "/mock/a.pdf"))

        // まだ何も読み込んでいないので、確定した種別は既定のまま。
        // URL は .pdf を指しているが、そちらへは追随しない。
        #expect(FileType(url: ref.url) == .pdf)
        #expect(ref.renderedFileType != FileType.pdf)
    }

    private static func makeController(surface: RecordingSurface) -> WebViewCommandController {
        let defaults = makeIsolatedDefaults(prefix: "DocumentSurfaceDispatchTests")
        let store = ViewerStore(defaults: defaults)
        return WebViewCommandController(
            surfaces: DocumentSurfaces(webRenderer: surface),
            perFileState: PerFileStateStore(defaults: defaults),
            currentDocument: CurrentDocumentRef(
                store: store, initialURL: URL(fileURLWithPath: "/mock/a.md")
            ),
            onZoomChanged: { _ in },
            onScrollPositionSaved: { _, _, _ in },
            capabilities: { .allEnabledForTesting }
        )
    }
}
