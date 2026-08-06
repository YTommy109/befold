import SwiftUI

/// Help > 機能説明 の中身。主要機能を静的な箇条書きで紹介する。
struct FeatureOverviewView: View {
    private struct Feature: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let detail: String
    }

    /// ブックマークの説明文はキー表記を含むため、実際の割り当て（`BookmarkShortcut`）を
    /// 差し込む。文言側に ⌘D を直書きすると、差分表示を露出するビルドで ⌘B へ移った
    /// ときに説明だけが古いまま残る。
    static func bookmarksDetail(shortcut: String = BookmarkShortcut.displayName) -> String {
        String(format: String(localized: "featureOverview.bookmarks.detail", bundle: .l10n), shortcut)
    }

    private let features: [Feature] = [
        Feature(title: "featureOverview.livePreview.title", detail: Self.text("featureOverview.livePreview.detail")),
        Feature(title: "featureOverview.tabs.title", detail: Self.text("featureOverview.tabs.detail")),
        Feature(title: "featureOverview.bookmarks.title", detail: FeatureOverviewView.bookmarksDetail()),
        Feature(title: "featureOverview.quickOpen.title", detail: Self.text("featureOverview.quickOpen.detail")),
        Feature(title: "featureOverview.hiddenFiles.title", detail: Self.text("featureOverview.hiddenFiles.detail")),
        Feature(
            title: "featureOverview.sourceToggle.title",
            detail: Self.text("featureOverview.sourceToggle.detail")
        ),
    ]

    private static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .l10n)
    }

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
