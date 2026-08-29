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
/// `BEFOLD_SNAPSHOT_GROUPING=0` を足すと桁区切りを切った状態で撮る。
@MainActor
@Suite
struct SettingsViewSnapshotTests {
    @Test("設定ビューがオフスクリーンで描画できる")
    func rendersOffscreen() throws {
        // 桁区切りを切った状態も撮れるようにしておく(見本がその設定に連動する)。
        let grouping = ProcessInfo.processInfo.environment["BEFOLD_SNAPSHOT_GROUPING"] != "0"
        let rep = try Self.renderSettingsView(grouping: grouping)
        #expect(rep.pixelsWide > 0)

        guard let outputPath = ProcessInfo.processInfo.environment["BEFOLD_SNAPSHOT_PATH"] else {
            return
        }
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

    /// 4 つの選択肢の見本は右揃えの固定幅列に入れてあるので、**行ごとの右端が
    /// 揃う**。左揃えだと符号の幅の差(- と ▲)で同じ 1,234 が行ごとに別の位置から
    /// 始まり、見比べられない(ユーザー指摘で直した箇所)。
    ///
    /// 判定はビットマップから行を切り出して右端を数える。ラジオの 4 行は
    /// この画面の**最後**に並ぶので、地でない行のかたまりの末尾 4 つを見る。
    /// Section の並びを変えるとここが落ちるが、そのときは測る対象を選び直すべき
    /// なので、黙って通るより落ちるほうがよい。
    @Test("負の数の選択肢の見本が右端で揃っている")
    func negativeSamplesAreRightAligned() throws {
        let rep = try Self.renderSettingsView()
        let rows = Self.inkRowBands(in: rep).suffix(4)
        #expect(rows.count == 4)

        let rightEdges = rows.compactMap { Self.rightmostInkColumn(in: rep, rows: $0) }
        #expect(rightEdges.count == 4)
        let spread = (rightEdges.max() ?? 0) - (rightEdges.min() ?? 0)
        // 1px の許容は、黒い文字と赤い文字でアンチエイリアスの端が 1 つずれるため
        // (実測: 揃っている状態で [334, 334, 333, 333])。左揃えに戻すと符号の幅の
        // 差だけずれるので、この許容では通らない。
        #expect(spread <= 1, "見本の右端がばらついている: \(rightEdges)")
    }

    /// 地でない行が連続するかたまり(= テキストの行)の範囲を返す。
    private static func inkRowBands(in rep: NSBitmapImageRep) -> [Range<Int>] {
        var bands: [Range<Int>] = []
        var start: Int?
        for row in 0 ..< rep.pixelsHigh {
            let hasInk = rowHasInk(in: rep, row: row)
            if hasInk, start == nil {
                start = row
            } else if !hasInk, let began = start {
                bands.append(began ..< row)
                start = nil
            }
        }
        if let began = start {
            bands.append(began ..< rep.pixelsHigh)
        }
        return bands
    }

    private static func rowHasInk(in rep: NSBitmapImageRep, row: Int) -> Bool {
        rightmostInkColumn(in: rep, rows: row ..< (row + 1)) != nil
    }

    /// 指定した行範囲で、地でないいちばん右のピクセルの x。無ければ nil。
    /// 地の判定は inkPixelCount と同じ閾値だが、Section の淡い背景まで拾うと
    /// 右端が常に枠の端になってしまうので、**文字として濃い**ピクセルだけを見る。
    private static func rightmostInkColumn(in rep: NSBitmapImageRep, rows: Range<Int>) -> Int? {
        var rightmost: Int?
        for row in rows {
            for column in stride(from: rep.pixelsWide - 1, through: 0, by: -1) {
                guard let color = rep.colorAt(x: column, y: row) else { continue }
                let converted = color.usingColorSpace(.sRGB) ?? color
                let brightness = (Double(converted.redComponent)
                    + Double(converted.greenComponent)
                    + Double(converted.blueComponent)) / 3
                if brightness < 0.6 {
                    if column > (rightmost ?? -1) {
                        rightmost = column
                    }
                    break
                }
            }
        }
        return rightmost
    }

    private static func renderSettingsView(grouping: Bool = true) throws -> NSBitmapImageRep {
        let defaults = makeIsolatedDefaults(prefix: "SettingsViewSnapshotTests")
        let numberPreference = CsvNumberFormatPreference(defaults: defaults)
        numberPreference.grouping = grouping
        let controller = HostedPanelWindowController(
            rootView: SettingsView(
                preference: CodeFontPreference(defaults: defaults),
                onChange: {},
                numberPreference: numberPreference,
                onNumberChange: {}
            ),
            title: "Settings",
            resizable: false
        )
        controller.showAndActivate()
        defer { controller.window?.close() }
        let window = try #require(controller.window)
        // 明色の外観に固定する。このファイルの判定はどれも「地はほぼ白、文字は暗い」
        // を前提にしており(rightmostInkColumn の brightness < 0.6、inkPixelCount の
        // 0.9 閾値)、ダークモードの実機では地のほうが暗くなって全行が文字と判定され、
        // 行のかたまりが 1 つに潰れる(実測: rows.count が 4 ではなく 1 になる)。
        // 測りたいのは配置の揃いであって外観ではないので、撮る側を固定する。
        window.appearance = NSAppearance(named: .aqua)
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
