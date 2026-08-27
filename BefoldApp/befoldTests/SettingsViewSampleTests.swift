@testable import befold
import BefoldKit
import Testing

/// 負の数の選択肢に添える見本の文字列。
///
/// 描画したピクセルからでは「カンマが入っているか」を測れないので、文字列を
/// 直接読む。見本は**上の桁区切りスイッチに連動する**——切っているのに見本だけ
/// カンマ付きだと、選んだ結果と違うものを見せることになる。
@MainActor
@Suite
struct SettingsViewSampleTests {
    @Test("桁区切りが入なら見本にカンマが入る")
    func groupedSamplesHaveSeparator() {
        #expect(SettingsView.negativeStyleSample(.plain, grouping: true) == "-1,234")
        #expect(SettingsView.negativeStyleSample(.red, grouping: true) == "-1,234")
        #expect(SettingsView.negativeStyleSample(.triangle, grouping: true) == "▲1,234")
        #expect(SettingsView.negativeStyleSample(.triangleRed, grouping: true) == "▲1,234")
    }

    @Test("桁区切りが切なら見本からカンマが消える")
    func ungroupedSamplesHaveNoSeparator() {
        #expect(SettingsView.negativeStyleSample(.plain, grouping: false) == "-1234")
        #expect(SettingsView.negativeStyleSample(.red, grouping: false) == "-1234")
        #expect(SettingsView.negativeStyleSample(.triangle, grouping: false) == "▲1234")
        #expect(SettingsView.negativeStyleSample(.triangleRed, grouping: false) == "▲1234")
    }

    /// ▲ 表記は符号そのものを置き換える(▲ と - を併記しない)。viewer 側の
    /// formatCsvNumber と同じ約束で、ここが食い違うと見本が嘘になる。
    @Test("▲ 表記の見本にマイナス記号が残らない")
    func triangleSamplesDropMinusSign() {
        for grouping in [true, false] {
            for style in [CsvNegativeStyle.triangle, .triangleRed] {
                #expect(!SettingsView.negativeStyleSample(style, grouping: grouping).contains("-"))
            }
        }
    }
}
