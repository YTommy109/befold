import AppKit
@testable import befold
import Testing

@Suite
@MainActor
struct FileMenuTitleLayoutTests {
    @Test("ファイル名とパスがタブ区切りの 2 列になる")
    func splitsNameAndPathIntoTwoColumns() {
        let layout = FileMenuTitleLayout(urls: [URL(fileURLWithPath: "/tmp/docs/diagram.mmd")])

        #expect(layout.attributedTitle(at: 0).string == "diagram.mmd\t/tmp/docs")
    }

    @Test("ホームディレクトリ配下のパスは ~ に畳まれる")
    func abbreviatesHomeDirectoryWithTilde() {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("note.md")
        let layout = FileMenuTitleLayout(urls: [url])

        #expect(layout.attributedTitle(at: 0).string == "note.md\t~")
    }

    @Test("長すぎるパスは先頭を省略して幅上限に収まる")
    func truncatesOverlongPathFromTheHead() {
        let deep = "/" + Array(repeating: "very-long-directory-name", count: 12).joined(separator: "/")
        let layout = FileMenuTitleLayout(urls: [URL(fileURLWithPath: deep + "/note.md")])

        let path = layout.attributedTitle(at: 0).string.split(separator: "\t")[1]
        #expect(path.hasPrefix("…/"))
        #expect(path.hasSuffix("very-long-directory-name"))
        let font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        #expect((String(path) as NSString).size(withAttributes: [.font: font]).width <= 320)
    }

    @Test("パス列は一覧全体で同じ右端のタブストップに揃う")
    func alignsPathColumnAcrossAllItems() {
        let layout = FileMenuTitleLayout(urls: [
            URL(fileURLWithPath: "/tmp/a.md"),
            URL(fileURLWithPath: "/tmp/very-long-file-name-that-is-wide.md"),
        ])

        let stops = (0 ... 1).map { index -> CGFloat in
            let style = layout.attributedTitle(at: index)
                .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            return style?.tabStops.first?.location ?? 0
        }
        #expect(stops[0] > 0)
        #expect(stops[0] == stops[1])
    }
}
