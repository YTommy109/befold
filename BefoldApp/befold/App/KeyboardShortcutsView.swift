import SwiftUI

/// Help > キーボードショートカット の中身。メニュー由来のショートカットに加え、
/// メニューを経由しない操作(ビューア内スクロール・サイドバー・Quick Open)も並べる。
/// 一覧をここに持たないのは、実装との乖離を構造的に起こさないため(TASK-240 / TASK-503)。
struct KeyboardShortcutsView: View {
    private let groups = HelpShortcutSections.all(isDocumentJumpEnabled: FeatureGate.isDocumentJumpEnabled)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.headline)
                            .textSelection(.enabled)
                        ForEach(group.entries) { entry in
                            HStack {
                                Text(entry.title)
                                    .textSelection(.enabled)
                                Spacer()
                                Text(entry.key)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 320)
    }
}
