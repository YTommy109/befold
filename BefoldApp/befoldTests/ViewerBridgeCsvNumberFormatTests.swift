import BefoldKit
import Foundation
import Testing

/// CSV/TSV の数値表示設定まわりのブリッジ契約テスト。
/// スクリプトの文字列生成と、JS 側の受理リストとの一致の両方をここで見る。
/// ViewerBridgeTests / ViewerBridgeContractTests から分けてあるのは
/// type_body_length を超えないため。
@Suite
@MainActor // ViewerBridgeContractTests.viewerBundleSource() が MainActor 隔離のため
struct ViewerBridgeCsvNumberFormatTests {
    @Test("csvNumberGroupingScript が真偽値を代入する")
    func csvNumberGroupingScriptEmitsBool() {
        #expect(ViewerCsvBridge.csvNumberGroupingScript(true) == "window._mmdCsvGrouping = true;")
        #expect(ViewerCsvBridge.csvNumberGroupingScript(false) == "window._mmdCsvGrouping = false;")
    }

    @Test("csvNegativeStyleScript が rawValue を文字列として代入する")
    func csvNegativeStyleScriptEmitsRawValue() {
        #expect(
            ViewerCsvBridge.csvNegativeStyleScript(.triangleRed)
                == "window._mmdCsvNegativeStyle = \"triangleRed\";"
        )
    }

    /// 注入だけでは反映されない(セルの HTML を組み直す必要がある)ため、
    /// 反映用スクリプトは末尾で入口関数を呼ぶところまでを含む。
    @Test("applyCsvNumberFormatScript が注入と反映呼び出しを続けて出す")
    func applyCsvNumberFormatScriptCallsEntryPoint() {
        let script = ViewerCsvBridge.applyCsvNumberFormatScript(
            grouping: false, negativeStyle: .triangle
        )

        #expect(script.contains("window._mmdCsvGrouping = false;"))
        #expect(script.contains("window._mmdCsvNegativeStyle = \"triangle\";"))
        #expect(script.hasSuffix("_mmdInitCsvNumberFormat();"))
    }

    /// CsvNegativeStyle の rawValue が JS 側の受理リストと一致することを検証する。
    ///
    /// Swift は enum、JS は文字列リテラルの配列で持っているため、片側だけ足しても
    /// コンパイルは通り、実行時に「未知の値」として既定へ倒れる(＝設定が黙って
    /// 効かない)。ここで機械的に突き合わせる。
    @Test("CsvNegativeStyle の rawValue が viewer-bundle.js の受理リストと一致する")
    func csvNegativeStylesMatchJSList() throws {
        let source = try ViewerBridgeContractTests.viewerBundleSource()
        // 個々の rawValue を contains で探すと、800KB のバンドル内の無関係な
        // 一致("plain" 等)で通ってしまう。受理リストの配列リテラルそのものを
        // 取り出して集合ごと突き合わせる。
        let marker = "var CSV_NEGATIVE_STYLES = ["
        let start = try #require(source.range(of: marker), "JS 側に受理リストが無い")
        let end = try #require(source.range(of: "]", range: start.upperBound ..< source.endIndex))
        let literal = source[start.upperBound ..< end.lowerBound]
        let jsStyles = literal
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: ["\""]) }

        #expect(jsStyles == CsvNegativeStyle.allCases.map(\.rawValue))
    }
}
