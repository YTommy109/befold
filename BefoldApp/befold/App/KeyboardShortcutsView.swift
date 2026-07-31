import SwiftUI

/// Help > キーボードショートカット の中身。メインメニューに実際に割り当てられている
/// ショートカットを MenuShortcutCatalog で抽出し、メニューごとにグループ化して一覧表示する。
/// 一覧をここに持たないのは、メニュー定義との乖離を構造的に起こさないため(TASK-240)。
struct KeyboardShortcutsView: View {
    private let groups = MenuShortcutCatalog.snapshot

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
