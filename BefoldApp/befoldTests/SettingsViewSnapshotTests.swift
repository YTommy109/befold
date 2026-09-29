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
        let rep = try grouping ? Self.rendered.get().rep : Self.renderSettingsView(grouping: false)
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
        let pixels = try Self.rendered.get().pixels
        #expect(Self.reddishPixelCount(in: pixels) > 0)
    }

    /// 中身が描けていること（真っ白でないこと）。ImageRenderer 経由では
    /// Form/.formStyle(.grouped) が描けず**真っ白な画像**になった（実測）。
    /// 同じ形で静かに空になったらここで落とす。
    @Test("描画結果が真っ白でない")
    func renderedContentIsNotBlank() throws {
        let pixels = try Self.rendered.get().pixels
        #expect(Self.inkPixelCount(in: pixels) > 0)
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
        let pixels = try Self.rendered.get().pixels
        let rows = Self.inkRowBands(in: pixels).suffix(4)
        #expect(rows.count == 4)

        let rightEdges = rows.compactMap { Self.rightmostInkColumn(in: pixels, rows: $0) }
        #expect(rightEdges.count == 4)
        let spread = (rightEdges.max() ?? 0) - (rightEdges.min() ?? 0)
        // 1px の許容は、黒い文字と赤い文字でアンチエイリアスの端が 1 つずれるため
        // (実測: 揃っている状態で [334, 334, 333, 333])。左揃えに戻すと符号の幅の
        // 差だけずれるので、この許容では通らない。
        #expect(spread <= 1, "見本の右端がばらついている: \(rightEdges)")
    }

    /// 地でない行が連続するかたまり(= テキストの行)の範囲を返す。
    private static func inkRowBands(in pixels: Pixels) -> [Range<Int>] {
        var bands: [Range<Int>] = []
        var start: Int?
        for row in 0 ..< pixels.height {
            let hasInk = rowHasInk(in: pixels, row: row)
            if hasInk, start == nil {
                start = row
            } else if !hasInk, let began = start {
                bands.append(began ..< row)
                start = nil
            }
        }
        if let began = start {
            bands.append(began ..< pixels.height)
        }
        return bands
    }

    private static func rowHasInk(in pixels: Pixels, row: Int) -> Bool {
        rightmostInkColumn(in: pixels, rows: row ..< (row + 1)) != nil
    }

    /// 指定した行範囲で、地でないいちばん右のピクセルの x。無ければ nil。
    /// 地の判定は inkPixelCount と同じ閾値だが、Section の淡い背景まで拾うと
    /// 右端が常に枠の端になってしまうので、**文字として濃い**ピクセルだけを見る。
    private static func rightmostInkColumn(in pixels: Pixels, rows: Range<Int>) -> Int? {
        var rightmost: Int?
        for row in rows {
            for column in stride(from: pixels.width - 1, through: 0, by: -1) {
                let color = pixels.rgb(column: column, row: row)
                if (color.red + color.green + color.blue) / 3 < 0.6 {
                    if column > (rightmost ?? -1) {
                        rightmost = column
                    }
                    break
                }
            }
        }
        return rightmost
    }

    /// 描画はどのテストでも同じなので 1 回だけ行う（窓の生成とピクセルの読み出しが重い）。
    /// 失敗も Result に閉じ込めて、各テストで同じ理由で落ちるようにする。
    private static let rendered: Result<(rep: NSBitmapImageRep, pixels: Pixels), any Error> = Result {
        let rep = try renderSettingsView()
        return try (rep, Pixels(rep))
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
            resizable: false,
            placement: .centered
        )
        // 表示もアクティベートもしない。cacheDisplay は画面に出ていない窓の中身も描ける。
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
    private static func reddishPixelCount(in pixels: Pixels) -> Int {
        countPixels(in: pixels) { red, green, blue in
            red > 0.55 && green < 0.45 && blue < 0.45
        }
    }

    /// 地（ほぼ白）でないピクセル数。
    private static func inkPixelCount(in pixels: Pixels) -> Int {
        countPixels(in: pixels) { red, green, blue in
            red < 0.9 || green < 0.9 || blue < 0.9
        }
    }

    private static func countPixels(
        in pixels: Pixels, matching predicate: (Double, Double, Double) -> Bool
    ) -> Int {
        var count = 0
        for row in stride(from: 0, to: pixels.height, by: 2) {
            for column in stride(from: 0, to: pixels.width, by: 2) {
                let color = pixels.rgb(column: column, row: row)
                if predicate(color.red, color.green, color.blue) {
                    count += 1
                }
            }
        }
        return count
    }
}

/// ビットマップを sRGB・8bit RGBA の既知形式へ描き直して生バイトで持つ。
/// `NSBitmapImageRep.colorAt` は 1 画素ごとに NSColor を作り、色空間の変換まで
/// 挟むので、全画素を走査すると遅い。y は上から数える(colorAt と同じ向き)。
private struct Pixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ rep: NSBitmapImageRep) throws {
        let image = try #require(rep.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    func rgb(column: Int, row: Int) -> RGB {
        let offset = (row * width + column) * 4
        return RGB(
            red: Double(bytes[offset]) / 255,
            green: Double(bytes[offset + 1]) / 255,
            blue: Double(bytes[offset + 2]) / 255
        )
    }
}
