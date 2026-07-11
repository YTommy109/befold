@testable import befold
import Foundation
import Testing

@Suite
struct CLIInstallerTests {
    @Test("シムスクリプトは指定の bundle path を open -a で呼び出す")
    func shimScriptContentsEmbedsBundlePath() {
        let script = CLIInstaller.shimScriptContents(bundlePath: "/Applications/befold.app")

        #expect(script.contains("#!/bin/bash"))
        #expect(script.contains("open -a '/Applications/befold.app' \"$@\""))
    }

    @Test("書き込み可能な場所には直接インストールされる")
    func installWritesShimDirectlyWhenWritable() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")

        let result = CLIInstaller.install(bundlePath: "/Applications/befold.app", installPath: installPath)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let contents = try String(contentsOf: installPath, encoding: .utf8)
        #expect(contents.contains("/Applications/befold.app"))
        let attributes = try FileManager.default.attributesOfItem(atPath: installPath.path)
        let permissions = attributes[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }
}
