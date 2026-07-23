@testable import befold
import Foundation
import Testing

@Suite
struct CLIShimInspectorTests {
    @Test("何も設置されていない場合は notInstalled")
    func statusIsNotInstalledWhenNothingExists() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")

        let status = CLIShimInspector.status(bundlePath: "/Applications/befold.app", installPath: installPath)

        #expect(status == .notInstalled)
    }

    @Test("現在のバンドル実行ファイルを指す symlink の場合は upToDate")
    func statusIsUpToDateWhenSymlinkMatchesCurrentBundle() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        try FileManager.default.createSymbolicLink(
            atPath: installPath.path,
            withDestinationPath: "/Applications/befold.app/Contents/MacOS/befold-cli"
        )

        let status = CLIShimInspector.status(bundlePath: "/Applications/befold.app", installPath: installPath)

        #expect(status == .upToDate)
    }

    @Test("実体ファイル(旧形式のシムスクリプト)の場合は legacyFile")
    func statusIsLegacyFileForRegularFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        try "#!/bin/bash\nexec open -a \"/Applications/befold.app\" \"$@\"\n".write(
            to: installPath, atomically: true, encoding: .utf8
        )

        let status = CLIShimInspector.status(bundlePath: "/Applications/befold.app", installPath: installPath)

        #expect(status == .legacyFile)
    }

    @Test("別のバンドルパスを指す symlink の場合は staleSymlink")
    func statusIsStaleSymlinkForMismatchedTarget() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        try FileManager.default.createSymbolicLink(
            atPath: installPath.path,
            withDestinationPath: "/Applications/befold-old.app/Contents/MacOS/befold-cli"
        )

        let status = CLIShimInspector.status(bundlePath: "/Applications/befold.app", installPath: installPath)

        #expect(status == .staleSymlink)
    }

    @Test("参照先が存在しないダングリング symlink でも staleSymlink 判定できる")
    func statusIsStaleSymlinkForDanglingSymlink() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        try FileManager.default.createSymbolicLink(
            atPath: installPath.path,
            withDestinationPath: "/no/such/path/befold"
        )

        let status = CLIShimInspector.status(bundlePath: "/Applications/befold.app", installPath: installPath)

        #expect(status == .staleSymlink)
    }
}
