import Foundation
@testable import befold
import Testing

/// 実ファイルシステム（一時ディレクトリ）を使う UpdateInstaller の結合テスト。
@Suite
struct UpdateInstallerIntegrationTests {
    @Test
    func findsAppBundleInMountPoint() throws {
        let tmp = try TempDir(prefix: "befold-installer-test")
        defer { withExtendedLifetime(tmp) {} }
        let app = tmp.url.appendingPathComponent("befold.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        #expect(UpdateInstaller.findApp(inMountPoint: tmp.url)?.lastPathComponent == "befold.app")
    }

    @Test
    func findAppReturnsNilForEmptyMountPoint() throws {
        let tmp = try TempDir(prefix: "befold-installer-test")
        defer { withExtendedLifetime(tmp) {} }

        #expect(UpdateInstaller.findApp(inMountPoint: tmp.url) == nil)
    }
}
