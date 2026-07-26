import Foundation
import Testing

/// QuickLook 拡張(.appex)の Info.plist / entitlements を実ファイルから読み、
/// 対象 UTI とサンドボックス設定のドリフトを検知する。
/// `swift test` では .appex をビルドできないため、ProjectYmlPackagingTests と同じ流儀で
/// 定義元どうしを突き合わせて担保する。
@Suite
struct QuickLookInfoPlistTests {
    private static var appDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldCLITests/
            .deletingLastPathComponent() // BefoldApp/
    }

    private static func plist(at relativePath: String) throws -> [String: Any] {
        let url = appDirectory.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(parsed as? [String: Any])
    }

    /// appex の NSExtensionAttributes.QLSupportedContentTypes。
    private static func supportedContentTypes() throws -> Set<String> {
        let info = try plist(at: "BefoldQuickLook/Info.plist")
        let ext = try #require(info["NSExtension"] as? [String: Any])
        let attributes = try #require(ext["NSExtensionAttributes"] as? [String: Any])
        let types = try #require(attributes["QLSupportedContentTypes"] as? [String])
        return Set(types)
    }

    /// アプリ本体が CFBundleDocumentTypes で「開ける」と宣言している UTI の和集合。
    /// befold がどの UTI を扱うかの単一情報源。
    private static func appDocumentContentTypes() throws -> Set<String> {
        let info = try plist(at: "befold/Info.plist")
        let documentTypes = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        return Set(documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
    }

    /// SVG はアプリ本体の CFBundleDocumentTypes には無いが QuickLook では対象にする。
    /// 実機の UTType(filenameExtension: "svg") は public.svg-image に解決されるため、
    /// レンダリング表示するにはこの UTI を宣言するしかない(TASK-72.4 で方針決定)。
    private static let quickLookOnlyContentTypes: Set<String> = ["public.svg-image"]

    /// .ts(TypeScript)は実機で public.mpeg-2-transport-stream(動画)に解決されるが、
    /// この UTI を宣言する QuickLook 拡張が befold だけの状態にしても macOS は内蔵
    /// プレビューアを優先し appex を呼ばない(2026-07-26 / macOS 26.5.2 で実機確認)。
    /// 効かない宣言は本物の .ts 動画のプレビューを奪うリスクだけが残るため宣言しない。
    @Test("QLSupportedContentTypes は動画 UTI を含まない")
    func supportedContentTypesExcludeTransportStream() throws {
        let supported = try Self.supportedContentTypes()

        #expect(!supported.contains("public.mpeg-2-transport-stream"))
    }

    @Test("QLSupportedContentTypes はアプリ本体の CFBundleDocumentTypes と SVG のみで構成される")
    func supportedContentTypesMirrorAppDocumentTypes() throws {
        let supported = try Self.supportedContentTypes()
        let expected = try Self.appDocumentContentTypes().union(Self.quickLookOnlyContentTypes)

        #expect(supported == expected)
    }

    /// PDF・画像は macOS 標準の QuickLook に任せるため、対象 UTI に含めない
    /// (SVG はレンダリング表示のため例外として上で許可している)。
    @Test("QLSupportedContentTypes は PDF・画像の UTI を含まない", arguments: [
        "com.adobe.pdf", "public.pdf", "public.png", "public.jpeg", "com.compuserve.gif",
        "org.webmproject.webp", "com.microsoft.bmp", "com.microsoft.ico", "public.image",
    ])
    func supportedContentTypesExcludeBinaryPreviewTypes(uti: String) throws {
        let supported = try Self.supportedContentTypes()

        #expect(!supported.contains(uti))
    }

    /// network.client は WKWebView の動作要件であり、外部通信のために付けているのではない。
    /// サンドボックス下の WKWebView はローカルコンテンツのみでも WebKit の Networking
    /// プロセスを起動するため、これが無いと Networking プロセスが起動できず、連鎖して
    /// WebContent も上がらず、あらゆるロードが完了しないまま空白のプレビューになる
    /// (実機で loadHTMLString すら url=nil のまま完了しないことを確認済み)。
    /// 外部への通信自体は viewer.html 側の CSP と
    /// `RendererFeatures.quickLookRestricted` で塞ぐ。
    @Test("appex の entitlements はサンドボックス有効で、WKWebView 要件の network.client のみを持つ")
    func entitlementsEnableSandboxWithWebKitRequirement() throws {
        let entitlements = try Self.plist(at: "BefoldQuickLook/BefoldQuickLook.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.server"] == nil)
    }
}
