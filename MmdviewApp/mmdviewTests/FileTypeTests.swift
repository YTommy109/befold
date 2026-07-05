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
        ("pdf", FileType.pdf),
        ("PDF", FileType.pdf),
    ])
    func knownExtensions(ext: String, expected: FileType) {
        let url = URL(fileURLWithPath: "/a/b.\(ext)")
        #expect(FileType(url: url) == expected)
    }

    /// 画像拡張子が .image(mimeType:) にマッピングされること
    @Test(arguments: [
        ("png", "image/png"),
        ("jpg", "image/jpeg"),
        ("jpeg", "image/jpeg"),
        ("gif", "image/gif"),
        ("webp", "image/webp"),
        ("bmp", "image/bmp"),
        ("ico", "image/x-icon"),
        ("PNG", "image/png"),
        ("JPG", "image/jpeg"),
    ])
    func imageExtensionsMapToMimeType(ext: String, mimeType: String) {
        let url = URL(fileURLWithPath: "/a/b.\(ext)")
        #expect(FileType(url: url) == .image(mimeType: mimeType))
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
        (FileType.image(mimeType: "image/png"), "image"),
        (FileType.pdf, "pdf"),
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
        #expect(FileType.image(mimeType: "image/png").codeLanguage == nil)
        #expect(FileType.pdf.codeLanguage == nil)
    }

    /// csvDelimiter は .csv のときだけ区切り文字を返すこと
    @Test
    func csvDelimiterOnlyForCsv() {
        #expect(FileType.csv(delimiter: ",").csvDelimiter == ",")
        #expect(FileType.csv(delimiter: "\t").csvDelimiter == "\t")
        #expect(FileType.mmd.csvDelimiter == nil)
        #expect(FileType.markdown.csvDelimiter == nil)
        #expect(FileType.code(language: "swift").csvDelimiter == nil)
        #expect(FileType.image(mimeType: "image/png").csvDelimiter == nil)
        #expect(FileType.pdf.csvDelimiter == nil)
    }

    /// imageMimeType は .image のときだけ MIME タイプを返すこと
    @Test
    func imageMimeTypeOnlyForImage() {
        #expect(FileType.image(mimeType: "image/png").imageMimeType == "image/png")
        #expect(FileType.image(mimeType: "image/jpeg").imageMimeType == "image/jpeg")
        #expect(FileType.mmd.imageMimeType == nil)
        #expect(FileType.pdf.imageMimeType == nil)
        #expect(FileType.code(language: "swift").imageMimeType == nil)
    }

    /// isBinaryContent は image/pdf のときだけ true を返すこと
    @Test
    func isBinaryContentOnlyForImageAndPdf() {
        #expect(FileType.image(mimeType: "image/png").isBinaryContent == true)
        #expect(FileType.pdf.isBinaryContent == true)
        #expect(FileType.mmd.isBinaryContent == false)
        #expect(FileType.markdown.isBinaryContent == false)
        #expect(FileType.svg.isBinaryContent == false)
        #expect(FileType.code(language: "swift").isBinaryContent == false)
    }

    /// isRenderable は mmd/markdown/svg/html/csv/image/pdf で true を返すこと
    @Test
    func isRenderable() {
        #expect(FileType.mmd.isRenderable == true)
        #expect(FileType.markdown.isRenderable == true)
        #expect(FileType.svg.isRenderable == true)
        #expect(FileType.html.isRenderable == true)
        #expect(FileType.csv(delimiter: ",").isRenderable == true)
        #expect(FileType.image(mimeType: "image/png").isRenderable == true)
        #expect(FileType.pdf.isRenderable == true)
        #expect(FileType.code(language: "swift").isRenderable == false)
    }

    /// supportsSourceMode はテキスト由来のレンダリング可能種別のみ true を返すこと
    @Test
    func supportsSourceModeOnlyForRenderableTextTypes() {
        #expect(FileType.mmd.supportsSourceMode == true)
        #expect(FileType.markdown.supportsSourceMode == true)
        #expect(FileType.svg.supportsSourceMode == true)
        #expect(FileType.html.supportsSourceMode == true)
        #expect(FileType.csv(delimiter: ",").supportsSourceMode == true)
        #expect(FileType.image(mimeType: "image/png").supportsSourceMode == false)
        #expect(FileType.pdf.supportsSourceMode == false)
        #expect(FileType.code(language: "swift").supportsSourceMode == false)
    }

    /// renderLangArgument は code/csv/image のときだけ第 3 引数を返すこと
    @Test
    func renderLangArgumentByType() {
        #expect(FileType.code(language: "swift").renderLangArgument == "swift")
        #expect(FileType.csv(delimiter: ",").renderLangArgument == ",")
        #expect(FileType.csv(delimiter: "\t").renderLangArgument == "\t")
        #expect(FileType.image(mimeType: "image/png").renderLangArgument == "image/png")
        #expect(FileType.mmd.renderLangArgument == nil)
        #expect(FileType.markdown.renderLangArgument == nil)
        #expect(FileType.svg.renderLangArgument == nil)
        #expect(FileType.html.renderLangArgument == nil)
        #expect(FileType.pdf.renderLangArgument == nil)
    }

    /// 拡張子リストに重複がないこと（対応表と mermaid/markdown/svg/html の衝突検知）
    @Test
    func extensionListsHaveNoDuplicates() {
        let all = FileType.mermaidExtensions + FileType.markdownExtensions + FileType.codeExtensions
            + FileType.svgExtensions + FileType.htmlExtensions
            + FileType.csvExtensions + FileType.tsvExtensions
            + [String](FileType.imageExtensionMimeTypes.keys)
            + FileType.pdfExtensions
        #expect(Set(all).count == all.count)
    }

    /// 対応表のキーがすべて小文字であること（判定は lowercased() で行うため）
    @Test
    func codeExtensionKeysAreLowercase() {
        for key in FileType.codeExtensionLanguages.keys {
            #expect(key == key.lowercased())
        }
    }

    /// 画像拡張子対応表のキーがすべて小文字であること
    @Test
    func imageExtensionKeysAreLowercase() {
        for key in FileType.imageExtensionMimeTypes.keys {
            #expect(key == key.lowercased())
        }
    }
}
