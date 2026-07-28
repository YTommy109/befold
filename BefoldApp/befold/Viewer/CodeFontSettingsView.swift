import SwiftUI

/// フォント設定ウィンドウの中身。CodeFontPreference は @Observable ではないため、
/// ローカルの @State を保持しつつ変更のたびに書き戻す(write-through)方式を取る。
@MainActor
struct CodeFontSettingsView: View {
    private let preference: CodeFontPreference
    private let onChange: () -> Void

    @State private var fontFamily: String?
    @State private var fontSizePoints: Double
    private let familyNames: [String]

    init(preference: CodeFontPreference, onChange: @escaping () -> Void) {
        self.preference = preference
        self.onChange = onChange
        _fontFamily = State(initialValue: preference.fontFamily)
        _fontSizePoints = State(initialValue: preference.fontSizePoints)
        familyNames = MonospaceFontCatalog.systemMonospaceFamilyNames()
    }

    var body: some View {
        Form {
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
                    fontSizePoints = preference.fontSizePoints
                    onChange()
                }
            }

            Section(String(localized: "settings.codeFont.preview", bundle: .l10n)) {
                Text(String(localized: "settings.codeFont.sampleCode", bundle: .l10n))
                    .font(previewFont)
                    .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var previewFont: Font {
        if let fontFamily {
            .custom(fontFamily, size: fontSizePoints)
        } else {
            .system(size: fontSizePoints, design: .monospaced)
        }
    }
}
