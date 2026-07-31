import AppKit
import BefoldKit
import SwiftUI

/// About ウィンドウの中身。OGP 画像とアプリ情報を表示する。
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(contentsOfFile: ogpImagePath) ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("befold")
                        .font(.headline)
                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Link("Copyright © 2026 Tommy109", destination: AppLinks.homepage)
                        .font(.footnote)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 260)
    }

    private var ogpImagePath: String {
        Bundle.main.path(forResource: "AboutOGP", ofType: "png") ?? ""
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        return VersionFormatting.versionString(short: short ?? "", build: build)
    }
}
