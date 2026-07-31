import SwiftUI

/// Help > AI コーディングエージェント連携 の中身。
struct AIIntegrationView: View {
    private let exampleSkill: String

    init() {
        if let url = Bundle.appResources.url(forResource: "befold-review-skill", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            exampleSkill = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            exampleSkill = String(localized: "aiIntegration.loadFailed", bundle: .l10n)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("aiIntegration.detail")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(exampleSkill)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
