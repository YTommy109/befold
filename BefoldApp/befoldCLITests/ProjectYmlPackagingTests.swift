import BefoldCLI
import Foundation
import Testing

/// XcodeGen の project.yml を実ファイルから読み、CLI 配布に必要なパッケージング設定の
/// ドリフトを検知する。`swift test` では .app バンドルを組み立てられないため、
/// 「befold-cli が befold.app に同梱される」ことはここで定義元を突き合わせて担保する
/// (BefoldCLICommandTests の MARKETING_VERSION 突き合わせと同じ流儀)。
@Suite
struct ProjectYmlPackagingTests {
    /// project.yml のうち、アプリターゲット `befold` の定義ブロックだけを切り出す。
    /// 同名のスキーム定義(`schemes:` 配下)と取り違えないよう、`type: application` を目印にする。
    private static func appTargetBlock() throws -> String {
        let projectYmlURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldCLITests/
            .deletingLastPathComponent() // BefoldApp/
            .appendingPathComponent("project.yml")
        let lines = try String(contentsOf: projectYmlURL, encoding: .utf8)
            .components(separatedBy: .newlines)

        let start = try #require(
            lines.indices.first { lines[$0] == "  befold:" && lines[safe: $0 + 1] == "    type: application" }
        )
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("  ") && !$0.hasPrefix("   ") } ?? lines.endIndex
        return lines[start ..< end].joined(separator: "\n")
    }

    @Test("project.yml は befold-cli を befold.app の Contents/MacOS へ同梱する")
    func appTargetEmbedsCLIExecutable() throws {
        let block = try Self.appTargetBlock()

        #expect(block.contains("- target: befold-cli"))
        #expect(block.contains("destination: executables"))
    }

    @Test("project.yml の PRODUCT_BUNDLE_IDENTIFIER が AppBundle.identifier と一致する")
    func appTargetBundleIdentifierMatchesConstant() throws {
        let block = try Self.appTargetBlock()

        #expect(block.contains("PRODUCT_BUNDLE_IDENTIFIER: \(AppBundle.identifier)"))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
