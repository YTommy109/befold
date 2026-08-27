import AppKit
import BefoldKit
import SwiftUI

/// 設定ウィンドウの中身。項目ごとに Section を分けた 1 枚の Form で、タブは持たない。
///
/// 各 Preference 型は @Observable ではないため、ローカルの @State を保持しつつ
/// 変更のたびに書き戻す(write-through)方式を取る。書き戻したあとに対応する
/// onChange クロージャを呼び、開いている全ウィンドウへ反映させる。
@MainActor
struct SettingsView: View {
    private let preference: CodeFontPreference
    private let onChange: () -> Void
    private let numberPreference: CsvNumberFormatPreference
    private let onNumberChange: () -> Void

    @State private var fontFamily: String?
    @State private var fontSizePoints: Double
    @State private var csvGrouping: Bool
    @State private var csvNegativeStyle: CsvNegativeStyle
    private let familyNames: [String]

    init(
        preference: CodeFontPreference,
        onChange: @escaping () -> Void,
        numberPreference: CsvNumberFormatPreference,
        onNumberChange: @escaping () -> Void
    ) {
        self.preference = preference
        self.onChange = onChange
        self.numberPreference = numberPreference
        self.onNumberChange = onNumberChange
        _fontFamily = State(initialValue: preference.fontFamily)
        _fontSizePoints = State(initialValue: preference.fontSizePoints ?? CodeFontPreference.defaultPoints)
        _csvGrouping = State(initialValue: numberPreference.grouping)
        _csvNegativeStyle = State(initialValue: numberPreference.negativeStyle)
        familyNames = MonospaceFontCatalog.systemMonospaceFamilyNames()
    }

    var body: some View {
        Form {
            Section(String(localized: "settings.codeFont.windowTitle", bundle: .l10n)) {
                Picker(String(localized: "settings.codeFont.family", bundle: .l10n), selection: $fontFamily) {
                    Text(String(localized: "settings.codeFont.systemDefault", bundle: .l10n))
                        .tag(String?.none)
                    ForEach(familyNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .onChange(of: fontFamily) { _, newValue in
                    preference.fontFamily = newValue
                    onChange()
                }

                HStack {
                    Text(String(localized: "settings.codeFont.size", bundle: .l10n))
                    Stepper(
                        value: $fontSizePoints,
                        in: CodeFontPreference.minPoints ... CodeFontPreference.maxPoints,
                        step: 1
                    ) {
                        Text(fontSizePoints, format: .number)
                    }
                    .onChange(of: fontSizePoints) { _, newValue in
                        preference.fontSizePoints = newValue
                        fontSizePoints = preference.fontSizePoints ?? CodeFontPreference.defaultPoints
                        onChange()
                    }
                }
            }

            Section(String(localized: "settings.codeFont.preview", bundle: .l10n)) {
                // プレビュー用フォントは見本テキストにのみ適用する。ダイアログ他部分へ
                // 波及しないよう、この Text 以外に .font(previewFont) を付けないこと。
                Text(String(localized: "settings.codeFont.sampleCode", bundle: .l10n))
                    .font(previewFont)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 4)
            }

            // 数値表示はコードフォントと別の関心なので Section を分ける。
            // 「プレビュー」はコードフォントの見本なので、フォントの Section の
            // 直後に残し、この Section をその後ろへ置く。
            Section(String(localized: "settings.number.section", bundle: .l10n)) {
                Toggle(
                    String(localized: "settings.number.grouping", bundle: .l10n),
                    isOn: $csvGrouping
                )
                .onChange(of: csvGrouping) { _, newValue in
                    numberPreference.grouping = newValue
                    onNumberChange()
                }

                // ラジオボタンにして 4 つの表示例を同時に見せる。ポップアップだと
                // 選択中のものしか見えず、「▲ と赤字がどう出るか」を比べられない。
                Picker(
                    String(localized: "settings.number.negative", bundle: .l10n),
                    selection: $csvNegativeStyle
                ) {
                    ForEach(CsvNegativeStyle.allCases, id: \.self) { style in
                        Self.negativeStyleLabel(style, grouping: csvGrouping, columns: negativeLabelColumns)
                            .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: csvNegativeStyle) { _, newValue in
                    numberPreference.negativeStyle = newValue
                    onNumberChange()
                }
            }
        }
        .formStyle(.grouped)
        // Form 全体の既定フォントを本文サイズに固定し、見本テキストの .font が
        // 環境経由で他行へ継承されないようにする。
        .font(.body)
        // コードフォントと数値表示の Section が別物として見分けられる幅。
        // AppDelegate+HostedPanels の .settings は resizable: false なので、
        // ここが実効的な窓幅になる。
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 負の数の表記の選択肢ラベル。名前のあとに**その設定での見え方の例**を並べる。
    /// 赤字を選ぶ 2 つは例そのものを赤で描くので、選ばなくても結果が分かる。
    /// 名前を固定幅の枠に入れるのは、見本の開始位置を 4 行で揃えて見比べられる
    /// ようにするため(名前の長さがまちまちだと見本がばらばらの位置から始まる)。
    ///
    /// 見本は**上の桁区切りスイッチにも連動する**。桁区切りを切っているのに
    /// 見本だけカンマ付きだと、選んだ結果と違うものを見せることになる。
    private static func negativeStyleLabel(
        _ style: CsvNegativeStyle, grouping: Bool, columns: LabelColumns
    ) -> some View {
        var sample = Text(Self.negativeStyleSample(style, grouping: grouping)).monospacedDigit()
        if style == .red || style == .triangleRed {
            sample = sample.foregroundColor(.red)
        }
        return HStack(spacing: 0) {
            Text(Self.negativeStyleName(style))
                .frame(width: columns.name, alignment: .leading)
            // 見本は**右揃え**。符号の幅が違う(- と ▲)ので、左揃えだと同じ
            // 1,234 が行ごとに別の位置から始まって見比べにくい。
            sample.frame(width: columns.sample, alignment: .trailing)
        }
    }

    /// 選択肢ラベルの 2 列の幅。
    struct LabelColumns {
        let name: CGFloat
        let sample: CGFloat
    }

    /// 選択肢の表示名。CsvNegativeStyle は BefoldKit(ローカライズを持たない層)に
    /// あるため、表示名はこちら側で対応づける。
    private static func negativeStyleName(_ style: CsvNegativeStyle) -> String {
        switch style {
        case .plain: String(localized: "settings.number.negative.plain", bundle: .l10n)
        case .triangle: String(localized: "settings.number.negative.triangle", bundle: .l10n)
        case .red: String(localized: "settings.number.negative.red", bundle: .l10n)
        case .triangleRed: String(localized: "settings.number.negative.triangleRed", bundle: .l10n)
        }
    }

    /// 選択肢ラベルの 2 列の幅。**4 行で縦に揃える**ために、それぞれ 4 つのうち
    /// いちばん広いものに合わせる。名前の長さはロケールで変わる(ja「▲ + 赤字」/
    /// en「Triangle and red」)ので、定数ではなく実測した幅を使う。
    private var negativeLabelColumns: LabelColumns {
        let font = NSFont.preferredFont(forTextStyle: .body)
        func widest(_ texts: [String]) -> CGFloat {
            texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        }
        // 見本の幅は桁区切りの有無で変わるので、いま表示する側で測る。
        let samples = CsvNegativeStyle.allCases.map {
            Self.negativeStyleSample($0, grouping: csvGrouping)
        }
        // 実際に描かれるフォントが計測に使ったものと厳密に一致する保証はないので、
        // 端が詰まらないよう少し足す。
        return LabelColumns(
            name: widest(CsvNegativeStyle.allCases.map(Self.negativeStyleName)) + 12,
            sample: widest(samples) + 4
        )
    }

    /// 選択肢に添える見え方の例。**表示中の CSV とは無関係の固定の見本**で、
    /// 実際の整形は viewer 側(viewer-src/csv-html.ts)が行う。ここは同じ規則を
    /// 実装し直すのではなく、決め打ちの文字列を並べているだけ。
    ///
    /// 桁区切りのスイッチに連動させるのは、切っているのに見本だけカンマ付きだと
    /// 選んだ結果と違うものを見せることになるため。`private` にしていないのは
    /// SettingsViewSampleTests がこの 8 通りを直接読んで検証するため
    /// (描画のピクセルからでは「カンマが入っているか」を測れない)。
    static func negativeStyleSample(_ style: CsvNegativeStyle, grouping: Bool) -> String {
        let digits = grouping ? "1,234" : "1234"
        return switch style {
        case .plain, .red: "-" + digits
        case .triangle, .triangleRed: "\u{25B2}" + digits
        }
    }

    private var previewFont: Font {
        if let fontFamily {
            .custom(fontFamily, size: fontSizePoints)
        } else {
            .system(size: fontSizePoints, design: .monospaced)
        }
    }
}
