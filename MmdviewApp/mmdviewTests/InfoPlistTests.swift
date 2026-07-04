import Foundation
@testable import mmdview
import Testing

/// Info.plist のファイルタイプ宣言を検証する。
/// .md の UTI は環境によって net.daringfireball.markdown / com.unknown.md 等に
/// バインドが変わるため、mmdview 自身が UTI を宣言し、実勢 UTI も claim している
/// ことを回帰テストとして固定する。
@Suite
struct InfoPlistTests {
    private func loadPlist() -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // mmdviewTests/
            .deletingLastPathComponent() // MmdviewApp/
            .appendingPathComponent("mmdview/Info.plist")
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

    /// mmdview 自身が net.daringfireball.markdown を宣言していること。
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
                ($0["LSItemContentTypes"] as? [String])?.contains("com.degino.mmdview.mermaid-diagram") == true
            }
        )
        #expect(mermaid["LSHandlerRank"] as? String == "Owner")
    }
}
