import Foundation
@testable import mmdview
import Testing

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
        ("svg", FileType.svg),
        ("SVG", FileType.svg),
        ("html", FileType.html),
        ("htm", FileType.html),
        ("HTML", FileType.html),
        ("csv", FileType.csv(delimiter: ",")),
        ("tsv", FileType.csv(delimiter: "\t")),
        ("CSV", FileType.csv(delimiter: ",")),
        ("TSV", FileType.csv(delimiter: "\t")),
    ])
    func knownExtensions(ext: String, expected: FileType) {
        let url = URL(fileURLWithPath: "/a/b.\(ext)")
        #expect(FileType(url: url) == expected)
    }

    /// コード拡張子が .code(language:) にマッピングされること（代表例＋大文字）
    @Test(arguments: [
        ("swift", "swift"),
        ("py", "python"),
        ("go", "go"),
        ("rs", "rust"),
        ("mjs", "javascript"),
        ("tsx", "typescript"),
        ("kt", "kotlin"),
        ("hpp", "cpp"),
        ("zsh", "bash"),
        ("toml", "ini"),
        ("json", "json"),
        ("jsonc", "json"),
        ("yml", "yaml"),
        ("plist", "xml"),
        ("PY", "python"),
        ("Swift", "swift"),
    ])
    func codeExtensionsMapToLanguage(ext: String, language: String) {
        let url = URL(fileURLWithPath: "/a/b.\(ext)")
        #expect(FileType(url: url) == .code(language: language))
    }

    /// 未知の拡張子は plaintext(等幅プレーンテキスト表示)にフォールバックすること
    @Test(arguments: ["txt", ""])
    func unknownExtensionsFallbackToPlaintext(ext: String) {
        let path = ext.isEmpty ? "/a/b" : "/a/b.\(ext)"
        let url = URL(fileURLWithPath: path)
        #expect(FileType(url: url) == .code(language: "plaintext"))
    }

    /// jsValue が JavaScript 側の期待する文字列を返すこと
    @Test(arguments: [
        (FileType.mmd, "mmd"),
        (FileType.markdown, "md"),
        (FileType.svg, "svg"),
        (FileType.html, "html"),
        (FileType.code(language: "swift"), "code"),
        (FileType.csv(delimiter: ","), "csv"),
    ])
    func jsValueMapping(fileType: FileType, expected: String) {
        #expect(fileType.jsValue == expected)
    }

    /// codeLanguage は .code のときだけ言語名を返すこと
    @Test
    func codeLanguageOnlyForCode() {
        #expect(FileType.code(language: "python").codeLanguage == "python")
        #expect(FileType.mmd.codeLanguage == nil)
        #expect(FileType.markdown.codeLanguage == nil)
        #expect(FileType.svg.codeLanguage == nil)
        #expect(FileType.html.codeLanguage == nil)
        #expect(FileType.csv(delimiter: ",").codeLanguage == nil)
    }

    /// csvDelimiter は .csv のときだけ区切り文字を返すこと
    @Test
    func csvDelimiterOnlyForCsv() {
        #expect(FileType.csv(delimiter: ",").csvDelimiter == ",")
        #expect(FileType.csv(delimiter: "\t").csvDelimiter == "\t")
        #expect(FileType.mmd.csvDelimiter == nil)
        #expect(FileType.markdown.csvDelimiter == nil)
        #expect(FileType.code(language: "swift").csvDelimiter == nil)
    }

    /// isRenderable は mmd/markdown/svg/html のときだけ true を返すこと
    @Test
    func isRenderable() {
        #expect(FileType.mmd.isRenderable == true)
        #expect(FileType.markdown.isRenderable == true)
        #expect(FileType.svg.isRenderable == true)
        #expect(FileType.html.isRenderable == true)
        #expect(FileType.csv(delimiter: ",").isRenderable == true)
        #expect(FileType.code(language: "swift").isRenderable == false)
    }

    /// 拡張子リストに重複がないこと（対応表と mermaid/markdown/svg/html の衝突検知）
    @Test
    func extensionListsHaveNoDuplicates() {
        let all = FileType.mermaidExtensions + FileType.markdownExtensions + FileType.codeExtensions
            + FileType.svgExtensions + FileType.htmlExtensions
            + FileType.csvExtensions + FileType.tsvExtensions
        #expect(Set(all).count == all.count)
    }

    /// 対応表のキーがすべて小文字であること（判定は lowercased() で行うため）
    @Test
    func codeExtensionKeysAreLowercase() {
        for key in FileType.codeExtensionLanguages.keys {
            #expect(key == key.lowercased())
        }
    }
}
