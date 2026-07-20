@testable import befold
import Foundation
import Testing

@Suite
struct CLIInstallerTests {
    @Test("シムスクリプトは bundle 内の実行ファイルを直接 exec する")
    func shimScriptContentsEmbedsBundlePath() {
        let script = CLIInstaller.shimScriptContents(bundlePath: "/Applications/befold.app")

        #expect(script.contains("#!/bin/bash"))
        #expect(script.contains("exec '/Applications/befold.app/Contents/MacOS/befold' \"$@\""))
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
