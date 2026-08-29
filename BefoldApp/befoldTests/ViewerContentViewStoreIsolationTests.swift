import Foundation
import Testing

/// プレビュー領域がファイル単位の保存ストアを見ないことを固定する
/// (ADR 0002「文書の状態の規則」1 / TASK-388)。
///
/// 描画へ渡る値は `initialZoom: store.zoom` / `scrollPositionToRestore:
/// store.scrollPositionToRestore` の 2 つで、いずれも窓のライブ値。ここへ
/// `ZoomStore` / `WindowPresentationMemory` を渡すと、body の再評価のたびに保存値・記憶を
/// 読み直すことになり、他窓が書いた値を生きている窓が拾う。
///
/// この回帰は `ViewerWindowStateIndependenceTests` では検知できない。あちらが見る
/// `store.zoom` は正しい値のまま、描画へ渡る値だけがずれるため。SwiftUI の `body` は
/// opaque で、組み立てた `View` から実際に渡した値を取り出す手段が無いので、
/// ソースの参照そのものを走査して固定する。
///
/// **走査対象は 2 ファイル**。TASK-564.6 で描画面への配線を
/// `ViewerContentView` から `DocumentSurfaceStack` へ移したため、片方だけを見ると
/// 「配線を移した先で保存ストアを読む」形が素通りする。禁止語の検査は両方に掛ける。
@Suite
struct ViewerContentViewStoreIsolationTests {
    private static let viewerDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // befoldTests
        .deletingLastPathComponent() // BefoldApp
        .appendingPathComponent("befold/Viewer")

    private static let contentViewPath = viewerDirectory
        .appendingPathComponent("ViewerContentView.swift")
    /// 実際にレンダラへ値を渡している側。live 値の検査はこちらを見る。
    private static let surfaceStackPath = viewerDirectory
        .appendingPathComponent("DocumentSurfaceStack.swift")

    /// 面の側。宛先でないときに値を素通ししていないかはこちらを見る。
    private static let webViewPath = viewerDirectory
        .appendingPathComponent("ViewerWebView.swift")

    private static let isolatedPaths = [contentViewPath, surfaceStackPath]

    /// 参照を禁じる識別子。`perFileState` は 2 つのストアの入れ物なので、
    /// 束ねて渡す抜け道もここで塞ぐ。
    private static let forbiddenSymbols = [
        "ZoomStore", "WindowPresentationMemory", "PerFileStateStore", "perFileState",
    ]

    /// doc コメント・行コメントを除いたコード行。禁止語は doc コメントで
    /// 「渡さない」理由として言及されているため、コメントは対象外にする。
    private static func codeLines(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    @Test("プレビュー領域はファイル単位の保存ストアを参照しない")
    func doesNotReferenceStoredStateStores() throws {
        for path in Self.isolatedPaths {
            let source = try String(contentsOf: path, encoding: .utf8)
            let lines = Self.codeLines(in: source)
            for symbol in Self.forbiddenSymbols {
                let offenders = lines.filter { $0.contains(symbol) }
                #expect(
                    offenders.isEmpty,
                    "\(path.lastPathComponent) が \(symbol) を参照している: \(offenders)"
                )
            }
        }
    }

    /// 上の検査が「ファイルを読めていないから通っている」空振りでないことを確かめる。
    /// 実際に渡している値の名前が消えたら、検査対象がずれている。
    @Test("描画へ渡しているのは窓のライブ値である")
    func passesLiveWindowStateToRenderer() throws {
        let source = try String(contentsOf: Self.surfaceStackPath, encoding: .utf8)
        #expect(source.contains("initialZoom: store.zoom"))
        #expect(source.contains("scrollPositionToRestore: store.scrollPositionToRestore"))
    }

    /// **宛先でない面へファイル単位の値を流し込まない。**
    ///
    /// `PageZoomProjector.desired` は代入と同時に viewer.js へ適用する。面が 2 枚
    /// ある以上、PDF へ切り替える瞬間に PDF の倍率を web の面へ渡すと、**まだ見えて
    /// いる Markdown の倍率が変わってから** PDF に切り替わり、ちらついて見える
    /// （TASK-567 の実測）。web の面が宛先かどうかは `showsPDF` の裏返しで、
    /// 判定はサーフェス側 1 箇所に置く。
    @Test("宛先でない面へは倍率と復元位置を渡さない")
    func doesNotPushPerFileValuesToTheHiddenSurface() throws {
        let stack = try String(contentsOf: Self.surfaceStackPath, encoding: .utf8)
        #expect(stack.contains("ownsDocument: !showsPDF"))

        let webView = try String(contentsOf: Self.webViewPath, encoding: .utf8)
        let lines = Self.codeLines(in: webView)
        let guardIndex = try #require(lines.firstIndex { $0.contains("if ownsDocument {") })
        let zoomIndex = try #require(lines.firstIndex { $0.contains("renderer.initialPageZoom") })
        let positionIndex = try #require(
            lines.firstIndex { $0.contains("renderer.scrollPositionToRestore") }
        )
        // 代入が 2 つとも guard の内側にある（外へ出たら素通しへ戻る）。
        #expect(zoomIndex > guardIndex)
        #expect(positionIndex > guardIndex)
        let closing = try #require(lines[guardIndex...].firstIndex { $0.trimmingCharacters(
            in: .whitespaces
        ) == "}" })
        #expect(zoomIndex < closing)
        #expect(positionIndex < closing)
    }

    /// 配線の移設が「`ViewerContentView` に残ったまま二重化した」形になっていないこと。
    /// 描画面への引数はサーフェス側 1 箇所に閉じる。
    @Test("ViewerContentView は描画面へ直接配線しない")
    func contentViewDoesNotWireRendererDirectly() throws {
        let source = try String(contentsOf: Self.contentViewPath, encoding: .utf8)
        let lines = Self.codeLines(in: source)
        #expect(!lines.contains { $0.contains("ViewerWebView(") })
    }
}
