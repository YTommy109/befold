import Foundation
import Testing
@testable import mmdview

struct UpdateInstallerTests {
    @Test
    func installedAppURLAcceptsAppBundle() {
        let bundle = URL(fileURLWithPath: "/Applications/mmdview.app")
        #expect(UpdateInstaller.installedAppURL(bundleURL: bundle) == bundle)
    }

    @Test
    func installedAppURLRejectsDevBuildDirectory() {
        let devDir = URL(fileURLWithPath: "/Users/dev/mmdview/.build/debug")
        #expect(UpdateInstaller.installedAppURL(bundleURL: devDir) == nil)
    }

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

    @Test
    func updaterScriptContainsAllSteps() {
        let script = UpdateInstaller.updaterScript(
            appInDMG: "/Volumes/mmdview v1.2.0/mmdview.app",
            installedApp: "/Applications/mmdview.app",
            mountPoint: "/Volumes/mmdview v1.2.0",
            dmgPath: "/tmp/mmdview-update.dmg",
            pid: 12345)

        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("kill -0 12345"))
        #expect(script.contains(#"rm -rf "/Applications/mmdview.app""#))
        #expect(script.contains(#"cp -R "/Volumes/mmdview v1.2.0/mmdview.app" "/Applications/mmdview.app""#))
        #expect(script.contains(#"hdiutil detach "/Volumes/mmdview v1.2.0" -force"#))
        #expect(script.contains(#"rm -f "/tmp/mmdview-update.dmg""#))
        #expect(script.contains(#"xattr -dr com.apple.quarantine "/Applications/mmdview.app""#))
        #expect(script.contains(#"open "/Applications/mmdview.app""#))
        #expect(script.contains(#"rm -f "$0""#))
    }
}
