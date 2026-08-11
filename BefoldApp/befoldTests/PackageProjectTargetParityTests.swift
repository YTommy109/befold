import Foundation
import Testing

/// Package.swift（swift test 経路）と project.yml（xcodebuild 経路）のターゲット構成が
/// 黙ってずれないようにする。片方にだけターゲットを足すと、そのターゲットに依存する
/// テストがもう一方の経路で丸ごとビルド不能になる（実測: BefoldTestSupport が
/// project.yml に無く、befoldTests が `unable to resolve module dependency` で
/// 1 本も走っていなかった。TASK-439）。
///
/// 意図的なずれは下の 2 つの許容集合に明記し、それ以外のずれは失敗させる。
@Suite
struct PackageProjectTargetParityTests {
    /// project.yml にだけ存在してよいターゲット。
    /// BefoldQuickLook は appex であり SwiftPM ではビルドできない。
    private static let projectOnlyTargets: Set<String> = ["BefoldQuickLook"]

    /// Package.swift にだけ存在してよいターゲット。
    /// befoldCLITests は `@testable import befold_cli` で実行ファイルターゲットの中身に
    /// 触るため Xcode ではテストホストが要るが、Xcode は plain tool を TEST_HOST として
    /// 受け付けない。載せるには CLI ロジックを BefoldCLI framework へ移す必要がある。
    private static let packageOnlyTargets: Set<String> = ["befoldCLITests"]

    private static func appDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests/
            .deletingLastPathComponent() // BefoldApp/
    }

    private static func lines(of fileName: String) throws -> [String] {
        let url = appDirectory().appendingPathComponent(fileName)
        return try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
    }

    /// `.target(` / `.executableTarget(` / `.testTarget(` の直後の `name:` を拾う。
    private static func packageTargetNames() throws -> Set<String> {
        let lines = try lines(of: "Package.swift")
        var names: Set<String> = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isTargetCall = trimmed == ".target(" || trimmed == ".executableTarget("
                || trimmed == ".testTarget("
            guard isTargetCall, index + 1 < lines.count else { continue }
            let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
            guard next.hasPrefix("name: \""), let name = next.split(separator: "\"").dropFirst().first
            else { continue }
            names.insert(String(name))
        }
        return names
    }

    /// トップレベルの `targets:` 配下にある 2 スペースインデントのキーを拾う。
    /// `schemes:` 配下の `targets:` はインデントが深いため混ざらない。
    private static func projectTargetNames() throws -> Set<String> {
        let lines = try lines(of: "project.yml")
        guard let start = lines.firstIndex(of: "targets:") else { return [] }
        var names: Set<String> = []
        for line in lines[(start + 1)...] {
            if !line.isEmpty, !line.hasPrefix(" ") { break }
            guard line.hasPrefix("  "), !line.hasPrefix("   "), line.hasSuffix(":") else { continue }
            names.insert(String(line.dropFirst(2).dropLast()))
        }
        return names
    }

    @Test("Package.swift と project.yml のターゲット構成が一致する（既知の例外を除く）")
    func targetSetsMatchExceptKnownExceptions() throws {
        let packageTargets = try Self.packageTargetNames()
        let projectTargets = try Self.projectTargetNames()

        // パースが壊れていないことの下限チェック（空集合同士の一致で通さない）。
        #expect(packageTargets.contains("BefoldTestSupport"))
        #expect(projectTargets.contains("BefoldTestSupport"))

        #expect(packageTargets.subtracting(projectTargets) == Self.packageOnlyTargets)
        #expect(projectTargets.subtracting(packageTargets) == Self.projectOnlyTargets)
    }
}
