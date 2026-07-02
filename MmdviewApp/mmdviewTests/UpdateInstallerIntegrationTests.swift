import Foundation
import Testing
@testable import mmdview

/// 実ファイルシステム（一時ディレクトリ）を使う UpdateInstaller の結合テスト。
@Suite
struct UpdateInstallerIntegrationTests {
    @Test
    func findsAppBundleInMountPoint() throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-installer-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mountPoint) }
        let app = mountPoint.appendingPathComponent("mmdview.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        #expect(UpdateInstaller.findApp(inMountPoint: mountPoint)?.lastPathComponent == "mmdview.app")
    }

    @Test
    func findAppReturnsNilForEmptyMountPoint() throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-installer-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mountPoint) }
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        #expect(UpdateInstaller.findApp(inMountPoint: mountPoint) == nil)
    }
}
