import Testing
import Foundation
@testable import mmdview

@Suite
struct FileTypeTests {
    /// 既知の拡張子が正しいファイル種別にマッピングされること（大文字小文字を含む）
    @Test(arguments: [
        ("mmd", FileType.mmd),
        ("mermaid", FileType.mmd),
        ("MMD", FileType.mmd),
        ("Mermaid", FileType.mmd),
        ("md", FileType.markdown),
        ("markdown", FileType.markdown),
        ("MD", FileType.markdown),
        ("MARKDOWN", FileType.markdown),
    ])
    func knownExtensions(ext: String, expected: FileType) {
        let url = URL(fileURLWithPath: "/a/b.\(ext)")
        #expect(FileType(url: url) == expected)
    }

    /// 未知の拡張子は markdown にフォールバックすること
    @Test(arguments: ["txt", "html", "json", ""])
    func unknownExtensionsFallbackToMarkdown(ext: String) {
        let path = ext.isEmpty ? "/a/b" : "/a/b.\(ext)"
        let url = URL(fileURLWithPath: path)
        #expect(FileType(url: url) == .markdown)
    }

    /// jsValue が JavaScript 側の期待する文字列を返すこと
    @Test(arguments: [
        (FileType.mmd, "mmd"),
        (FileType.markdown, "md"),
    ])
    func jsValueMapping(fileType: FileType, expected: String) {
        #expect(fileType.jsValue == expected)
    }
}
