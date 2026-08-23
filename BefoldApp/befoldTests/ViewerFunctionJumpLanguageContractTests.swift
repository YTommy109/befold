@testable import befold
import BefoldKit
import Foundation
import Testing

/// 定義ジャンプ(TASK-485.4)の対応言語が、Swift と JS で一致していることを
/// 検証する契約テスト。
///
/// この集合は 2 箇所に独立して存在する。Swift 側 `FunctionJumpLanguages.supported` は
/// メニューを塞ぐためだけに持ち、どの行を定義とみなすかは JS 側の
/// `DEFINITION_PATTERNS` が持つ。片方だけ言語を足すと、
///
/// - JS だけ足す → メニューがグレーのまま使えない
/// - Swift だけ足す → メニューは有効なのに常に 0 件
///
/// のどちらも「何も落ちない」形で成立してしまう。`HeadingJumpLevels` が
/// `ViewerJumpLevelContractTests` で塞いだのと同じ穴なので、同じ手口で結ぶ。
@Suite
@MainActor // 借りる ViewerBridgeContractTests の static ヘルパーが @MainActor 隔離のため
struct ViewerFunctionJumpLanguageContractTests {
    @Test("viewer-bundle.js の FUNCTION_JUMP_LANGUAGES が FunctionJumpLanguages.supported と一致する")
    func supportedLanguagesMatchViewerTable() throws {
        let source = try ViewerBridgeContractTests.viewerBundleSource()

        #expect(try Self.jsStringArray(named: "FUNCTION_JUMP_LANGUAGES", in: source)
            == FunctionJumpLanguages.supported)
    }

    /// 対応言語がすべて highlight.js の言語名として実在することを、
    /// FileType の拡張子表に現れるかどうかで確かめる。
    ///
    /// 綴りを間違えると(例: "ts")、上の一致テストは Swift と JS が同じ間違いを
    /// していれば通ってしまう。対応言語はソース表示の言語名と同じ語彙でなければ
    /// ならないので、その語彙の側から裏を取る。
    @Test("対応言語はすべて FileType が実際に付ける言語名である")
    func supportedLanguagesAreRealFileTypeLanguages() {
        let known = Set(Self.sampleExtensions
            .compactMap { FileType(url: URL(fileURLWithPath: "a.\($0)")).codeLanguage })

        for language in FunctionJumpLanguages.supported {
            #expect(known.contains(language), "FileType が付けない言語名: \(language)")
        }
    }

    /// 対応言語 1 つにつき最低 1 つの拡張子。増やしたら足す。
    private static let sampleExtensions = ["swift", "py", "js", "ts"]

    /// `var NAME = ["a", "b"];` 形式の宣言から文字列集合を取り出す。
    private static func jsStringArray(named name: String, in source: String) throws -> Set<String> {
        let pattern = #"(?:var|let|const)\s+"# + name + #"\s*=\s*\[([^\]]*)\]\s*;"#
        let found = try ViewerBridgeContractTests.matches(of: pattern, in: source)
        let first = try #require(found.first, "JS 側に \(name) の配列宣言が見つからない")
        return Set(first[1].split(separator: ",").map { element in
            element.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"'"))
        })
    }
}
