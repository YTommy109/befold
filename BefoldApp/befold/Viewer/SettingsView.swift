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

                Picker(
                    String(localized: "settings.number.negative", bundle: .l10n),
                    selection: $csvNegativeStyle
                ) {
                    ForEach(CsvNegativeStyle.allCases, id: \.self) { style in
                        Text(Self.negativeStyleLabel(style)).tag(style)
                    }
                }
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

    /// 負の数の表記の選択肢ラベル。CsvNegativeStyle は BefoldKit(ローカライズを
    /// 持たない層)にあるため、表示名はこちら側で対応づける。
    private static func negativeStyleLabel(_ style: CsvNegativeStyle) -> String {
        switch style {
        case .plain: String(localized: "settings.number.negative.plain", bundle: .l10n)
        case .triangle: String(localized: "settings.number.negative.triangle", bundle: .l10n)
        case .red: String(localized: "settings.number.negative.red", bundle: .l10n)
        case .triangleRed: String(localized: "settings.number.negative.triangleRed", bundle: .l10n)
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
