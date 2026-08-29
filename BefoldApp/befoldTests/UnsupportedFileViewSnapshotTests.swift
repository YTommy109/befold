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

    /// 描かれた画のフィンガープリント。**明暗の閾値で数えない。**
    /// 外観（ライト/ダーク）で地と文字の明るさが入れ替わるため、
    /// 閾値で数えると全画素が「文字」に見えて 3 つの理由が同じ数になる
    /// （実測: どれも 310369 で区別できなかった）。画そのものを比べる。
    private func fingerprint(of rep: NSBitmapImageRep) -> Data {
        rep.representation(using: .png, properties: [:]) ?? Data()
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

    /// 新しい理由が既存の文言と**別のもの**として出ること。
    /// 同じ画になるなら、どれかの理由へ丸められている（区別した意味が無い）。
    @Test("壊れた PDF の文言は他の理由の文言と異なる")
    func damagedDocumentMessageDiffersFromOthers() throws {
        let damaged = try fingerprint(of: render(.damagedDocument))
        let tooLarge = try fingerprint(of: render(.fileTooLarge))
        let unsupported = try fingerprint(of: render(.unsupportedFormat))

        #expect(!damaged.isEmpty)
        #expect(damaged != tooLarge)
        #expect(damaged != unsupported)
        // 文言そのものも別であることを、リソースの引き当てでも押さえる。
        #expect(RejectReason.damagedDocument.localizedMessage != RejectReason.fileTooLarge.localizedMessage)
        #expect(!RejectReason.damagedDocument.localizedMessage.isEmpty)
    }
}
