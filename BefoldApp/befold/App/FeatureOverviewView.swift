import SwiftUI

/// Help > 機能説明 の中身。主要機能を静的な箇条書きで紹介する。
struct FeatureOverviewView: View {
    private struct Feature: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
    }

    private let features: [Feature] = [
        Feature(title: "featureOverview.livePreview.title", detail: "featureOverview.livePreview.detail"),
        Feature(title: "featureOverview.tabs.title", detail: "featureOverview.tabs.detail"),
        Feature(title: "featureOverview.bookmarks.title", detail: "featureOverview.bookmarks.detail"),
        Feature(title: "featureOverview.quickOpen.title", detail: "featureOverview.quickOpen.detail"),
        Feature(title: "featureOverview.hiddenFiles.title", detail: "featureOverview.hiddenFiles.detail"),
        Feature(title: "featureOverview.sourceToggle.title", detail: "featureOverview.sourceToggle.detail"),
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
