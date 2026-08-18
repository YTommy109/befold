@testable import befold
import BefoldKit
import Foundation
import Testing

/// 文書内ジャンプで選べる見出しレベルの集合が、Swift と JS で一致していることを
/// 検証する契約テスト（TASK-485.11）。
///
/// ViewerBridgeContractTests から分けてあるのは、あちらが 400 行の
/// `file_length` に届いていたため。ソースを読んで突合するという性質は同じなので、
/// ファイル探索・正規表現のヘルパーはあちらの static メンバを借りる。
@Suite
@MainActor // 借りる ViewerBridgeContractTests の static ヘルパーが @MainActor 隔離のため
struct ViewerJumpLevelContractTests {
    /// 選べる見出しレベルの集合が Swift と JS で一致することを検証する（TASK-485.11）。
    ///
    /// この集合はかつて Swift のフィルタ域・JS の `HEADING_LEVELS`・viewer.html の
    /// 静的なボタンの 3 箇所に独立して書かれていた。JS 側だけに h4 を足しても、
    /// ユーザーのトグルは jumpLevelsChanged → HeadingJumpLevels の初期化で黙って
    /// 落とされ、どのテストも落ちない状態だった。ボタンは HEADING_LEVELS から
    /// 生成するようにして HTML の重複を消し、残る 2 箇所をここで結ぶ。
    @Test("viewer-bundle.js の HEADING_LEVELS が HeadingJumpLevels.selectableLevels と一致する")
    func headingLevelsMatchSelectableLevels() throws {
        let source = try ViewerBridgeContractTests.viewerBundleSource()

        #expect(
            try Self.jsIntArray(named: "HEADING_LEVELS", in: source)
                == HeadingJumpLevels.selectableLevels
        )
    }

    /// レベルのトグルが viewer.html へ静的に置かれていないことを検証する。
    ///
    /// 上の一致テストは HTML を見ないため、ボタンだけが静的に戻ると
    /// 「JS のレベルを増やしてもボタンが出ない」ずれが再び作れてしまう。
    /// 入れ物（#mmd-jump-levels）だけがあり、中身が空であることを確かめる。
    @Test("viewer.html にレベルのトグルが静的に置かれていない")
    func headingLevelButtonsAreNotHardcodedInHTML() throws {
        let html = try String(contentsOf: ViewerBridgeContractTests.resourceURL("viewer.html"), encoding: .utf8)

        #expect(html.contains("id=\"mmd-jump-levels\""), "レベルトグルの入れ物が viewer.html にない")
        #expect(
            !html.contains("id=\"mmd-jump-level-h"),
            "レベルのトグルは HEADING_LEVELS から生成する（viewer.html へ静的に置かない）"
        )
    }

    /// `var NAME = [1, 2, 3];` 形式の宣言から整数配列を取り出す。
    ///
    /// 表記ではなく値で比べるのは jsNumber と同じ理由（esbuild が空白や表記を
    /// 正規化するため、Swift 側の配列の説明文字列とは一致しない）。
    private static func jsIntArray(named name: String, in source: String) throws -> [Int] {
        let pattern = #"(?:var|let|const)\s+"# + name + #"\s*=\s*\[([^\]]*)\]\s*;"#
        let found = try ViewerBridgeContractTests.matches(of: pattern, in: source)
        let first = try #require(found.first, "JS 側に \(name) の配列宣言が見つからない")
        return try first[1].split(separator: ",").map { element in
            let text = element.trimmingCharacters(in: .whitespacesAndNewlines)
            return try #require(Int(text), "\(name) の要素を整数として読めない: \(text)")
        }
    }
}
