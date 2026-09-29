import AppKit
@testable import befold
import BefoldKit
import SwiftUI
import Testing

/// 表示できないファイルのバナーを、オフスクリーン描画で確かめる。
///
/// PDF として開けないファイル（TASK-564.1 で足した `RejectReason.damagedDocument`）で
/// **本当に文言が出る**ことを見る。読み込みは成功しているので、理由を落とすと
/// バナーが出ないまま空白になる——それを画素で塞ぐ。
///
/// 画面キャプチャではなく `NSHostingView.cacheDisplay(in:to:)` なので TCC の許可は
/// 要らない（`SettingsViewSnapshotTests` と同じ手）。
@MainActor
@Suite
struct UnsupportedFileViewSnapshotTests {
    private func render(_ reason: RejectReason) throws -> NSBitmapImageRep {
        let view = NSHostingView(
            rootView: UnsupportedFileView(
                fileURL: URL(fileURLWithPath: "/files/doc.pdf"), rejectReason: reason
            )
        )
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 画に含まれる色の種類数。地一色なら 1 で、文字が乗っていれば増える。
    private func distinctColorCount(in rep: NSBitmapImageRep) -> Int {
        var colors: Set<String> = []
        for column in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for row in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: column, y: row) else { continue }
                colors.insert(color.description)
            }
        }
        return colors.count
    }

    @Test("壊れた PDF の理由でバナーの文言が描かれる")
    func drawsTheDamagedDocumentMessage() throws {
        let damaged = try render(.damagedDocument)

        // 地一色ではない = 文言が乗っている。
        #expect(distinctColorCount(in: damaged) > 1)
    }

    /// 新しい理由が既存の文言と**別のもの**として出ること。同じ文言なら、どれかの理由へ
    /// 丸められている（区別した意味が無い）。バナーは `rejectReason.localizedMessage` を
    /// そのまま描くので、文言が描かれること自体は上のテストに任せ、ここは描かずに
    /// 文言の引き当てを比べる（理由ごとに描いて PNG を比べていたのを TASK-662.7 で縮めた）。
    @Test("壊れた PDF の文言は他の理由の文言と異なる")
    func damagedDocumentMessageDiffersFromOthers() {
        let damaged = RejectReason.damagedDocument.localizedMessage

        #expect(!damaged.isEmpty)
        #expect(damaged != RejectReason.fileTooLarge.localizedMessage)
        #expect(damaged != RejectReason.unsupportedFormat.localizedMessage)
    }
}

/// PDF の右上に重ねる回転コントロール（TASK-564.5 / メニューから移設）。
@MainActor
@Suite
struct PDFRotationOverlayTests {
    private func hostingView(onRotate: @escaping (Int) -> Void) -> NSHostingView<PDFRotationOverlay> {
        let view = NSHostingView(rootView: PDFRotationOverlay(onRotate: onRotate))
        view.frame = NSRect(x: 0, y: 0, width: 120, height: 60)
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test("2 つのボタンが描かれる")
    func drawsTwoButtons() throws {
        let view = hostingView { _ in }
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        var colors: Set<String> = []
        for column in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for row in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                if let color = rep.colorAt(x: column, y: row) { colors.insert(color.description) }
            }
        }
        // 地一色ではない = アイコンが乗っている。
        #expect(colors.count > 1)
    }

    /// 読み上げ名と tooltip の文言が 2 つとも引けて、互いに違うこと。
    /// アイコンだけのボタンなので、名前が無いと VoiceOver で区別できない。
    /// 訳が日英そろっているかは `LocalizationTests`（全キーを見る）が担保する。
    @Test("回転ボタンの文言が 2 つとも引ける")
    func hasLocalizedLabels() {
        let clockwise = String(localized: "viewer.pdf.rotateClockwise", bundle: .l10n)
        let counterClockwise = String(localized: "viewer.pdf.rotateCounterClockwise", bundle: .l10n)

        #expect(!clockwise.isEmpty)
        #expect(!counterClockwise.isEmpty)
        #expect(clockwise != counterClockwise)
    }

    /// 押すと向きが窓へ届くこと（時計回りが正、反時計回りが負）。
    @Test("回転の向きがそのまま渡る")
    func passesTheDirection() {
        var received: [Int] = []
        let overlay = PDFRotationOverlay { received.append($0) }

        overlay.onRotate(90)
        overlay.onRotate(-90)

        #expect(received == [90, -90])
    }
}
