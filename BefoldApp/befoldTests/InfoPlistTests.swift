@testable import befold
import BefoldKit
import Foundation
import Testing

/// Info.plist のファイルタイプ宣言を検証する。
/// .md の UTI は環境によって net.daringfireball.markdown / com.unknown.md 等に
/// バインドが変わるため、befold 自身が UTI を宣言し、実勢 UTI も claim している
/// ことを回帰テストとして固定する。
@Suite
struct InfoPlistTests {
    private func loadPlist() -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests/
            .deletingLastPathComponent() // BefoldApp/
            .appendingPathComponent("befold/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any]
        else { return [:] }
        return dict
    }

    private var documentTypes: [[String: Any]] {
        loadPlist()["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
    }

    private var importedTypes: [[String: Any]] {
        loadPlist()["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []
    }

    private func claimedContentTypes() -> Set<String> {
        Set(documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
    }

    /// befold 自身が net.daringfireball.markdown を宣言していること。
    /// 他アプリの宣言に依存すると、宣言アプリがない環境で .md の関連付けが効かない。
    @Test
    func importsDaringfireballMarkdownType() throws {
        let markdown = try #require(
            importedTypes.first { ($0["UTTypeIdentifier"] as? String) == "net.daringfireball.markdown" }
        )
        let tags = try #require(markdown["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try #require(tags["public.filename-extension"] as? [String])
        #expect(extensions.contains("md"))
        #expect(extensions.contains("markdown"))
        let conforms = try #require(markdown["UTTypeConformsTo"] as? [String])
        #expect(conforms.contains("public.plain-text"))
    }

    /// Markdown のドキュメントタイプが実勢 UTI（com.unknown.md 含む）を claim していること。
    /// .md のバインドがどの UTI に転んでも「このアプリで開く」に載るようにする。
    @Test
    func claimsKnownMarkdownContentTypes() {
        let claimed = claimedContentTypes()
        #expect(claimed.contains("net.daringfireball.markdown"))
        #expect(claimed.contains("net.ia.markdown"))
        #expect(claimed.contains("com.unknown.md"))
    }

    /// Mermaid 用の自前 UTI が Owner として claim され続けていること。
    @Test
    func claimsMermaidDiagramTypeAsOwner() throws {
        let mermaid = try #require(
            documentTypes.first {
                ($0["LSItemContentTypes"] as? [String])?.contains("com.degino.befold.mermaid-diagram") == true
            }
        )
        #expect(mermaid["LSHandlerRank"] as? String == "Owner")
    }

    /// コード全拡張子が befold 自身の source-code UTI 宣言に含まれていること。
    /// FileType.codeExtensionLanguages と Info.plist のドリフトを検知する。
    @Test("All code extensions are declared in source-code UTI")
    func importsSourceCodeTypeCoveringAllCodeExtensions() throws {
        let source = try #require(
            importedTypes.first {
                ($0["UTTypeIdentifier"] as? String) == "com.degino.befold.source-code"
            }
        )
        let tags = try #require(source["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try #require(tags["public.filename-extension"] as? [String])
        for ext in FileType.codeExtensions {
            #expect(extensions.contains(ext), "\(ext) が Info.plist に宣言されていない")
        }
        let conforms = try #require(source["UTTypeConformsTo"] as? [String])
        #expect(conforms.contains("public.source-code"))
    }

    /// Source Code のドキュメントタイプが自前 UTI と実勢システム UTI を claim していること。
    @Test("Source code document type claims required UTIs")
    func claimsSourceCodeContentTypes() {
        let claimed = claimedContentTypes()
        #expect(claimed.contains("com.degino.befold.source-code"))
        #expect(claimed.contains("public.source-code"))
        #expect(claimed.contains("public.swift-source"))
        #expect(claimed.contains("public.json"))
        #expect(claimed.contains("public.yaml"))
        #expect(claimed.contains("public.xml"))
    }

    /// CSV/TSV のドキュメントタイプが宣言されていること。
    @Test("CSV/TSV のドキュメントタイプが宣言されている")
    func claimsCsvTsvContentTypes() {
        let expectedUTIs: Set = [
            "public.comma-separated-values-text",
            "public.tab-separated-values-text",
        ]
        let claimed = claimedContentTypes()
        for uti in expectedUTIs {
            #expect(claimed.contains(uti), "Missing UTI: \(uti)")
        }
    }

    @Test("HTML のドキュメントタイプが宣言されている")
    func claimsHtmlContentType() {
        let claimed = claimedContentTypes()
        #expect(claimed.contains("public.html"))
    }
}
