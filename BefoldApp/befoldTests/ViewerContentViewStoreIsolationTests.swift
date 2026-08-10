import Foundation
import Testing

/// `ViewerContentView` がファイル単位の保存ストアを見ないことを固定する
/// (ADR 0002「文書の状態の規則」1 / TASK-388)。
///
/// 描画へ渡る値は `initialZoom: store.zoom` / `scrollPositionToRestore:
/// store.scrollPositionToRestore` の 2 つで、いずれも窓のライブ値。ここへ
/// `ZoomStore` / `ScrollPositionStore` を渡すと、body の再評価のたびに保存値を
/// 読み直すことになり、他窓が書いた値を生きている窓が拾う。
///
/// この回帰は `ViewerWindowStateIndependenceTests` では検知できない。あちらが見る
/// `store.zoom` は正しい値のまま、描画へ渡る値だけがずれるため。SwiftUI の `body` は
/// opaque で、組み立てた `View` から実際に渡した値を取り出す手段が無いので、
/// `FeatureGateEnumerationTests` と同じくソースの参照そのものを固定する。
@Suite
struct ViewerContentViewStoreIsolationTests {
    private static let contentViewPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // befoldTests
        .deletingLastPathComponent() // BefoldApp
        .appendingPathComponent("befold/Viewer/ViewerContentView.swift")

    /// 参照を禁じる識別子。`perFileState` は 2 つのストアの入れ物なので、
    /// 束ねて渡す抜け道もここで塞ぐ。
    private static let forbiddenSymbols = ["ZoomStore", "ScrollPositionStore", "PerFileStateStore", "perFileState"]

    /// doc コメント・行コメントを除いたコード行。禁止語は doc コメントで
    /// 「渡さない」理由として言及されているため、コメントは対象外にする。
    private static func codeLines(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    @Test("ViewerContentView はファイル単位の保存ストアを参照しない")
    func doesNotReferenceStoredStateStores() throws {
        let source = try String(contentsOf: Self.contentViewPath, encoding: .utf8)
        let lines = Self.codeLines(in: source)
        for symbol in Self.forbiddenSymbols {
            let offenders = lines.filter { $0.contains(symbol) }
            #expect(offenders.isEmpty, "ViewerContentView が \(symbol) を参照している: \(offenders)")
        }
    }

    /// 上の検査が「ファイルを読めていないから通っている」空振りでないことを確かめる。
    /// 実際に渡している値の名前が消えたら、検査対象がずれている。
    @Test("描画へ渡しているのは窓のライブ値である")
    func passesLiveWindowStateToRenderer() throws {
        let source = try String(contentsOf: Self.contentViewPath, encoding: .utf8)
        #expect(source.contains("initialZoom: store.zoom"))
        #expect(source.contains("scrollPositionToRestore: store.scrollPositionToRestore"))
    }
}
