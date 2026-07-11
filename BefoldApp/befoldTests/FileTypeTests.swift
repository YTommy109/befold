@testable import befold
import BefoldKit
import Foundation
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

    /// FileType の派生プロパティ(codeLanguage/csvDelimiter/imageMimeType/isBinaryContent/
    /// isRenderable/supportsSourceMode/renderLangArgument)の期待値セット。
    /// 期待値はプロダクトコードの switch をコピーせず、リテラルで書く。
    private struct FileTypeTraits: Sendable, CustomTestStringConvertible {
        let fileType: FileType
        let codeLanguage: String?
        let csvDelimiter: String?
        let imageMimeType: String?
        let isBinaryContent: Bool
        let isRenderable: Bool
        let supportsSourceMode: Bool
        let renderLangArgument: String?

        var testDescription: String {
            "\(fileType)"
        }
    }

    /// codeLanguage / csvDelimiter / imageMimeType / isBinaryContent / isRenderable /
    /// supportsSourceMode / renderLangArgument が種別ごとに正しい値を返すこと
    @Test(arguments: [
        FileTypeTraits(
            fileType: .mmd, codeLanguage: nil, csvDelimiter: nil, imageMimeType: nil,
            isBinaryContent: false, isRenderable: true, supportsSourceMode: true, renderLangArgument: nil
        ),
        FileTypeTraits(
            fileType: .markdown, codeLanguage: nil, csvDelimiter: nil, imageMimeType: nil,
            isBinaryContent: false, isRenderable: true, supportsSourceMode: true, renderLangArgument: nil
        ),
        FileTypeTraits(
            fileType: .svg, codeLanguage: nil, csvDelimiter: nil, imageMimeType: nil,
            isBinaryContent: false, isRenderable: true, supportsSourceMode: true, renderLangArgument: nil
        ),
        FileTypeTraits(
            fileType: .html, codeLanguage: nil, csvDelimiter: nil, imageMimeType: nil,
            isBinaryContent: false, isRenderable: true, supportsSourceMode: true, renderLangArgument: nil
        ),
        FileTypeTraits(
            fileType: .csv(delimiter: ","), codeLanguage: nil, csvDelimiter: ",", imageMimeType: nil,
            isBinaryContent: false, isRenderable: true, supportsSourceMode: true, renderLangArgument: ","
        ),
        FileTypeTraits(
            fileType: .csv(delimiter: "\t"), codeLanguage: nil, csvDelimiter: "\t", imageMimeType: nil,
            isBinaryContent: false, isRenderable: true, supportsSourceMode: true, renderLangArgument: "\t"
        ),
        FileTypeTraits(
            fileType: .image(mimeType: "image/png"), codeLanguage: nil, csvDelimiter: nil,
            imageMimeType: "image/png", isBinaryContent: true, isRenderable: true,
            supportsSourceMode: false, renderLangArgument: "image/png"
        ),
        FileTypeTraits(
            fileType: .image(mimeType: "image/jpeg"), codeLanguage: nil, csvDelimiter: nil,
            imageMimeType: "image/jpeg", isBinaryContent: true, isRenderable: true,
            supportsSourceMode: false, renderLangArgument: "image/jpeg"
        ),
        FileTypeTraits(
            fileType: .pdf, codeLanguage: nil, csvDelimiter: nil, imageMimeType: nil,
            isBinaryContent: true, isRenderable: true, supportsSourceMode: false, renderLangArgument: nil
        ),
        FileTypeTraits(
            fileType: .code(language: "python"), codeLanguage: "python", csvDelimiter: nil,
            imageMimeType: nil, isBinaryContent: false, isRenderable: false,
            supportsSourceMode: false, renderLangArgument: "python"
        ),
        FileTypeTraits(
            fileType: .code(language: "swift"), codeLanguage: "swift", csvDelimiter: nil,
            imageMimeType: nil, isBinaryContent: false, isRenderable: false,
            supportsSourceMode: false, renderLangArgument: "swift"
        ),
    ])
    private func fileTypeTraits(_ traits: FileTypeTraits) {
        #expect(traits.fileType.codeLanguage == traits.codeLanguage)
        #expect(traits.fileType.csvDelimiter == traits.csvDelimiter)
        #expect(traits.fileType.imageMimeType == traits.imageMimeType)
        #expect(traits.fileType.isBinaryContent == traits.isBinaryContent)
        #expect(traits.fileType.isRenderable == traits.isRenderable)
        #expect(traits.fileType.supportsSourceMode == traits.supportsSourceMode)
        #expect(traits.fileType.renderLangArgument == traits.renderLangArgument)
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
