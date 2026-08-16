import SwiftUI

/// Help > 機能説明 の中身。主要機能を静的な箇条書きで紹介する。
///
/// **説明文にキー表記（⌘P 等）を書かない。** ショートカットは Help > キーボードショートカットが
/// メニュー定義から生成して見せるものが単一の情報源で、こちらへ書き写すと割り当てを変えたときに
/// 説明文だけが古くなる（同じ乖離が TASK-240 で一度起きている）。この規約は
/// `LocalizationTests.featureDetailsDoNotSpellOutShortcuts` が担保する。
struct FeatureOverviewView: View {
    private struct Feature: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
    }

    /// 載せるのは主力機能だけ。網羅ではなく「何ができるアプリか」が分かることを狙う。
    private let features: [Feature] = [
        Feature(title: "featureOverview.formats.title", detail: "featureOverview.formats.detail"),
        Feature(title: "featureOverview.livePreview.title", detail: "featureOverview.livePreview.detail"),
        Feature(title: "featureOverview.displayModes.title", detail: "featureOverview.displayModes.detail"),
        Feature(title: "featureOverview.git.title", detail: "featureOverview.git.detail"),
        Feature(title: "featureOverview.sidebar.title", detail: "featureOverview.sidebar.detail"),
        Feature(title: "featureOverview.search.title", detail: "featureOverview.search.detail"),
        Feature(title: "featureOverview.tabs.title", detail: "featureOverview.tabs.detail"),
        Feature(title: "featureOverview.integrations.title", detail: "featureOverview.integrations.detail"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(features) { feature in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.title)
                            .font(.headline)
                            .textSelection(.enabled)
                        Text(feature.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 320)
    }
}
