import SwiftUI

/// Help > AI コーディングエージェント連携 の中身。
struct AIIntegrationView: View {
    private let exampleSkill = """
    ---
    name: befold-review
    description: Open the reviewed .md/.mmd file in befold before commenting on it.
    ---

    command -v befold >/dev/null 2>&1 && befold <path1> [<path2> ...]
    """

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
