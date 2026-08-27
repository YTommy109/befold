import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import SwiftUI
import Testing

/// 設定ウィンドウの中身をオフスクリーンで描画し、見た目を測る。
///
/// SwiftUI の中身はアクセシビリティ階層に出ないため、AX 経由では「見本が赤で
/// 出ているか」を測れない。画面キャプチャは対話セッションでしか撮れないので、
/// NSView のキャッシュ描画（画面キャプチャではないので TCC の許可も要らない）で
/// ビットマップを取り、そこから直接ピクセルを見る。
///
/// `BEFOLD_SNAPSHOT_PATH` を渡すと PNG も書き出す（目視確認用）。
@MainActor
@Suite
struct SettingsViewSnapshotTests {
    @Test("設定ビューがオフスクリーンで描画できる")
    func rendersOffscreen() throws {
        let defaults = makeIsolatedDefaults(prefix: "SettingsViewSnapshotTests")
        let view = SettingsView(
            preference: CodeFontPreference(defaults: defaults),
            onChange: {},
            numberPreference: CsvNumberFormatPreference(defaults: defaults),
            onNumberChange: {}
        )
        // ImageRenderer では描けない(Form/.formStyle(.grouped) は AppKit 実装で、
        // 実測すると真っ白な画像になる)。実ウィンドウへ載せて NSView の
        // キャッシュ描画で撮る。画面キャプチャではないので TCC の許可も要らない。
        let controller = HostedPanelWindowController(
            rootView: view, title: "Settings", resizable: false
        )
        controller.showAndActivate()
        defer { controller.window?.close() }
        let window = try #require(controller.window)
        // ヘッドレス実行ではウィンドウがまだ 0 高のことがある(実測: bounds が
        // (0,0,1,0) になり撮れなかった)。中身の固有サイズを測って明示的に与える。
        let contentView = try #require(window.contentView)
        window.setContentSize(contentView.fittingSize)
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        #expect(contentView.bounds.width > 0)

        guard let outputPath = ProcessInfo.processInfo.environment["BEFOLD_SNAPSHOT_PATH"] else {
            return
        }
        let rep = try #require(contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: outputPath))
    }

    /// 「赤字」「▲ + 赤字」の見本は赤で描く。文字色は Text.foregroundColor で
    /// 付けているが、Picker のラベルとして渡した Text の装飾が効くかは
    /// 実際に描いてみないと分からない（実測で効くことを確かめた上で、
    /// 効かなくなったらここで落とす）。
    @Test("負の数の選択肢に赤い見本が描かれる")
    func redSamplesAreRendered() throws {
        let rep = try Self.renderSettingsView()
        #expect(Self.reddishPixelCount(in: rep) > 0)
    }

    /// 中身が描けていること（真っ白でないこと）。ImageRenderer 経由では
    /// Form/.formStyle(.grouped) が描けず**真っ白な画像**になった（実測）。
    /// 同じ形で静かに空になったらここで落とす。
    @Test("描画結果が真っ白でない")
    func renderedContentIsNotBlank() throws {
        let rep = try Self.renderSettingsView()
        #expect(Self.inkPixelCount(in: rep) > 0)
    }

    private static func renderSettingsView() throws -> NSBitmapImageRep {
        let defaults = makeIsolatedDefaults(prefix: "SettingsViewSnapshotTests")
        let controller = HostedPanelWindowController(
            rootView: SettingsView(
                preference: CodeFontPreference(defaults: defaults),
                onChange: {},
                numberPreference: CsvNumberFormatPreference(defaults: defaults),
                onNumberChange: {}
            ),
            title: "Settings",
            resizable: false
        )
        controller.showAndActivate()
        defer { controller.window?.close() }
        let window = try #require(controller.window)
        let contentView = try #require(window.contentView)
        window.setContentSize(contentView.fittingSize)
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let rep = try #require(contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        return rep
    }

    /// 赤とみなすピクセル数。閾値は「赤成分が十分高く、緑と青がどちらも低い」で、
    /// 本文の黒・地の白・選択中ラジオのアクセント色のいずれにも当たらない。
    private static func reddishPixelCount(in rep: NSBitmapImageRep) -> Int {
        countPixels(in: rep) { red, green, blue in
            red > 0.55 && green < 0.45 && blue < 0.45
        }
    }

    /// 地（ほぼ白）でないピクセル数。
    private static func inkPixelCount(in rep: NSBitmapImageRep) -> Int {
        countPixels(in: rep) { red, green, blue in
            red < 0.9 || green < 0.9 || blue < 0.9
        }
    }

    private static func countPixels(
        in rep: NSBitmapImageRep, matching predicate: (Double, Double, Double) -> Bool
    ) -> Int {
        var count = 0
        for row in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for column in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let color = rep.colorAt(x: column, y: row) else { continue }
                let converted = color.usingColorSpace(.sRGB) ?? color
                if predicate(
                    Double(converted.redComponent),
                    Double(converted.greenComponent),
                    Double(converted.blueComponent)
                ) {
                    count += 1
                }
            }
        }
        return count
    }
}
