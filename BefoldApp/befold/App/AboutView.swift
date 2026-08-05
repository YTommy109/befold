import AppKit
import BefoldCLI
import BefoldKit
import SwiftUI

/// About ウィンドウの中身。OGP 画像とアプリ情報を表示する。
struct AboutView: View {
    /// OGP 画像。body で読むとビューの再評価ごとにディスクを読み直すため、
    /// 生成時に 1 度だけ読み込んで保持する。
    private let ogpImage: NSImage

    /// 表示用バージョン。取得経路は CLI(`--version`)と同じ AppVersion に寄せ、
    /// Info.plist が読めない場合も既知の版へフォールバックして空表示にしない。
    private let versionText: String

    init() {
        let path = Bundle.main.path(forResource: "AboutOGP", ofType: "png")
        ogpImage = path.flatMap { NSImage(contentsOfFile: $0) } ?? NSImage()
        versionText = AppVersion.resolvedWithBuild(infoDictionary: Bundle.main.infoDictionary)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: ogpImage)
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
                    Link("befold", destination: AppLinks.homepage)
                        .font(.headline)
                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("Copyright © 2026")
                        Link("Tommy109", destination: AppLinks.author)
                    }
                    .font(.footnote)
                }
                // バージョン・著作権表記は不具合報告で書き写す対象になるため、
                // 情報テキストはまとめて選択・コピーできるようにする。
                .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 260)
    }
}
