import SwiftUI

/// Help > AI コーディングエージェント連携 の中身。
struct AIIntegrationView: View {
    private let exampleSkill = """
    ---
    name: befold-review
    description: Open a Markdown/Mermaid file in the befold
      viewer so the user sees the rendered document, not raw
      source. Use when you wrote or updated a .md/.mmd file
      and are about to ask the user to review it.
    ---

    ## When to use

    Just before asking the user to review a .md / .mmd file
    you wrote or updated (design docs, plans, diagrams).
    Not when the user asks you to review a file - you read
    the source directly.

    ## Steps

    1. Collect the paths the user should look at.
    2. Right before the review request, open them:

       command -v befold >/dev/null 2>&1 \\
         && befold <path1> [<path2> ...]

    3. If befold is missing or fails, skip it and ask for
       the review as usual. The files stay watched, so your
       later edits refresh the same window.
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
