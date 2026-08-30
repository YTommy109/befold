@testable import befold
import BefoldKit
import Foundation
import Testing

/// **提示記憶へ書く向きは両面とも「切替直前の pull」1 本**（TASK-574.3）。
///
/// かつて web 面だけが、スクロールのたびに JS から位置を送る push も併せ持っていた。
/// その目的は「アプリ終了時やウィンドウ破棄時にも最新の位置が保存されるよう」で、
/// 位置を `UserDefaults` へ永続化していた頃のもの（36cdc7c5）。TASK-565 で永続化を
/// やめ窓の生存期間だけの記憶にした時点で目的が失われたため撤去した。
///
/// ここはソースを走査して、その撤去が戻っていないことを固定する。push を戻すと
/// 「面ごとに記憶へ届くタイミングが違う」状態が復活し、次に per-file な記憶を足す
/// たびに同じ二重構造が増える。
@Suite
struct PresentationMemoryWriteDirectionTests {
    /// スクロール位置の継続通知に使っていた名前。**どれか 1 つでも復活したら落ちる。**
    private static let retiredPushSymbols = [
        "scrollPositionChanged",
        "didChangeScrollPosition",
        "_MSG_SCROLL_POSITION_CHANGED",
        "_mmdPostScrollPosition",
        "_mmdInitScrollNotify",
    ]

    private static func sourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests
            .deletingLastPathComponent() // BefoldApp
        let searched = ["befold", "BefoldKit", "BefoldRenderKit", "viewer-src"]
            .map { root.appendingPathComponent($0) }
        var found: [URL] = []
        for directory in searched {
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in walker where ["swift", "ts"].contains(url.pathExtension) {
                found.append(url)
            }
        }
        return found
    }

    @Test("スクロール位置の継続通知(push)は復活していない")
    func scrollPositionPushStaysRetired() throws {
        var offenders: [String] = []
        for file in try Self.sourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in Self.retiredPushSymbols where text.contains(symbol) {
                offenders.append("\(file.lastPathComponent): \(symbol)")
            }
        }

        #expect(offenders.isEmpty, "撤去した push の名前が復活している: \(offenders)")
    }

    /// 位置を記憶へ書く入口が `recordScrollPosition` 1 つであること。
    /// 増えていたら、それは pull 以外の契機が生えたということ。
    @Test("記憶へ位置を書く入口は recordScrollPosition だけ")
    func onlyOneWriteEntryPoint() throws {
        let presenter = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("befold/App/ViewerDocumentPresenter.swift")
        let text = try String(contentsOf: presenter, encoding: .utf8)

        let writes = text.components(separatedBy: "presentationMemory.setScrollPosition").count - 1

        #expect(writes == 1, "setScrollPosition の呼び出しが \(writes) 箇所ある(期待 1)")
    }
}
