import Foundation
import Testing

/// FeatureGate の doc コメントに書かれた「露出点の列挙」が、実際のゲート参照と
/// 一致していることを検証する。列挙の更新を忘れたままゲート参照を足すと落ちる
/// （TASK-187 の撤去作業がコメントだけを頼りにしているため）。
@Suite
struct FeatureGateEnumerationTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // befoldTests
        .deletingLastPathComponent() // BefoldApp
        .appendingPathComponent("befold")

    private static let featureGatePath = sourceRoot
        .appendingPathComponent("App/FeatureGate.swift")

    private static let swiftLintConfigPath = sourceRoot
        .deletingLastPathComponent() // BefoldApp
        .appendingPathComponent(".swiftlint.yml")

    /// befold ターゲット配下の Swift ファイル一覧。
    private static func swiftFiles() throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: keys) else {
            throw EnumerationError.sourceRootUnreadable
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// doc コメントの `- \`Foo.bar\`` 行から型名を集める。
    private static func enumeratedTypes(in featureGateSource: String) -> Set<String> {
        var types: Set<String> = []
        for line in featureGateSource.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("/// - `") else { continue }
            let body = trimmed.dropFirst("/// - `".count)
            guard let end = body.firstIndex(where: { $0 == "`" || $0 == "." || $0 == "(" }) else { continue }
            types.insert(String(body[body.startIndex ..< end]))
        }
        return types
    }

    @Test("ゲートを参照する型の集合が FeatureGate のコメントの列挙と一致する")
    func enumerationCoversEveryGateReference() throws {
        let featureGateSource = try String(contentsOf: Self.featureGatePath, encoding: .utf8)
        var referencing: Set<String> = []
        for file in try Self.swiftFiles() where file.lastPathComponent != "FeatureGate.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("FeatureGate.") else { continue }
            referencing.insert(file.deletingPathExtension().lastPathComponent)
        }
        #expect(referencing == Self.enumeratedTypes(in: featureGateSource))
    }

    @Test("ゲートの参照は名前付きプロパティ経由に限る")
    func gateIsReferencedOnlyThroughNamedProperty() throws {
        var offenders: [String] = []
        for file in try Self.swiftFiles() where file.lastPathComponent != "FeatureGate.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("FeatureGate.inProgressFeaturesEnabled") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty)
    }

    /// `befold` ターゲット内での相対パス（`App/FeatureGate.swift` の形）。
    private static func relativePath(of file: URL) -> String {
        let root = sourceRoot.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    /// `.swiftlint.yml` の custom rule `feature_gate_direct_reference` の `excluded`
    /// （＝ゲートを読んでよい配線点の allowlist）を相対パス集合として読む。
    private static func lintAllowlist() throws -> Set<String> {
        let source = try String(contentsOf: swiftLintConfigPath, encoding: .utf8)
        guard let rule = source.range(of: "feature_gate_direct_reference:") else {
            throw EnumerationError.lintRuleMissing
        }
        let prefix = "- \"BefoldApp/befold/"
        var paths: Set<String> = []
        for line in source[rule.upperBound...].split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("regex:") { break }
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("$\"") else { continue }
            let body = trimmed.dropFirst(prefix.count).dropLast(2) // 末尾の `$"`
            paths.insert(body.replacingOccurrences(of: "\\", with: ""))
        }
        return paths
    }

    @Test("swiftlint の配線点 allowlist が実際のゲート参照と一致する")
    func lintAllowlistMatchesGateReferences() throws {
        var referencing: Set<String> = []
        referencing.insert("App/FeatureGate.swift")
        for file in try Self.swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("FeatureGate.") else { continue }
            referencing.insert(Self.relativePath(of: file))
        }
        #expect(try Self.lintAllowlist() == referencing)
    }

    private enum EnumerationError: Error {
        case sourceRootUnreadable
        case lintRuleMissing
    }
}
