import Foundation
@testable import mmdview
import Testing

/// 実ファイルシステム（一時ディレクトリ）を使う UpdateInstaller の結合テスト。
@Suite
struct UpdateInstallerIntegrationTests {
    @Test
    func findsAppBundleInMountPoint() throws {
        let tmp = try TempDir(prefix: "mmdview-installer-test")
        defer { withExtendedLifetime(tmp) {} }
        let app = tmp.url.appendingPathComponent("mmdview.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        #expect(UpdateInstaller.findApp(inMountPoint: tmp.url)?.lastPathComponent == "mmdview.app")
    }

    @Test
    func findAppReturnsNilForEmptyMountPoint() throws {
        let tmp = try TempDir(prefix: "mmdview-installer-test")
        defer { withExtendedLifetime(tmp) {} }

        #expect(UpdateInstaller.findApp(inMountPoint: tmp.url) == nil)
    }
}
