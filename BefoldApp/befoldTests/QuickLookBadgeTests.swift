import BefoldKit
import Testing

/// QuickLook 拡張のバッジ文字列の組み立て。
/// appex 自体は `swift test` からビルドできないため、表示文字列の生成だけを
/// BefoldKit の純粋関数として切り出し、ここで担保する。
@Suite
struct QuickLookBadgeTests {
    @Test("バージョンとビルド番号が揃っていれば両方を表示する")
    func showsVersionAndBuild() {
        let text = QuickLookBadge.text(infoDictionary: [
            "CFBundleShortVersionString": "1.7.3",
            "CFBundleVersion": "748",
        ])

        #expect(text == "befold QL, version 1.7.3 (748)")
    }

    @Test("ビルド番号が無ければバージョンだけを表示する")
    func showsVersionOnlyWithoutBuild() {
        let text = QuickLookBadge.text(infoDictionary: ["CFBundleShortVersionString": "1.7.3"])

        #expect(text == "befold QL, version 1.7.3")
    }

    /// バージョンが取れない場合でも、どの拡張が担当したかの識別だけは残す。
    @Test("infoDictionary が空なら名前だけを表示する")
    func fallsBackToNameOnlyWhenEmpty() {
        #expect(QuickLookBadge.text(infoDictionary: [:]) == "befold QL")
    }

    @Test("ビルド番号しか無ければ名前だけを表示する")
    func fallsBackToNameOnlyWithBuildAlone() {
        #expect(QuickLookBadge.text(infoDictionary: ["CFBundleVersion": "748"]) == "befold QL")
    }

    @Test("infoDictionary が nil でも落ちない")
    func handlesNilInfoDictionary() {
        #expect(QuickLookBadge.text(infoDictionary: nil) == "befold QL")
    }
}
