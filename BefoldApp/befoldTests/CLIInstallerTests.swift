@testable import befold
import Foundation
import Testing

@Suite
struct CLIInstallerTests {
    @Test("シムの参照先は bundle 内の実行ファイルである")
    func targetExecutablePathPointsIntoBundle() {
        let target = CLIInstaller.targetExecutablePath(bundlePath: "/Applications/befold.app")

        #expect(target == "/Applications/befold.app/Contents/MacOS/befold")
    }

    @Test("書き込み可能な場所には bundle 内の実行ファイルへの symlink が作成される")
    func installCreatesSymlinkWhenWritable() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")

        let result = CLIInstaller.install(bundlePath: "/Applications/befold.app", installPath: installPath)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: installPath.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: installPath.path)
        #expect(destination == "/Applications/befold.app/Contents/MacOS/befold")
    }

    @Test("旧バージョンの実体ファイルシムが残っていても symlink に置き換わる")
    func installReplacesLegacyRegularFileShim() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        try "#!/bin/bash\nexec open -a \"/Applications/befold.app\" \"$@\"\n".write(
            to: installPath, atomically: true, encoding: .utf8
        )

        let result = CLIInstaller.install(bundlePath: "/Applications/befold.app", installPath: installPath)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: installPath.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
    }

    @Test("古いバンドルパスを指す既存 symlink は新しい参照先に置き換わる")
    func installReplacesStaleSymlinkTarget() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        try FileManager.default.createSymbolicLink(
            atPath: installPath.path,
            withDestinationPath: "/Applications/befold-old.app/Contents/MacOS/befold"
        )

        let result = CLIInstaller.install(bundlePath: "/Applications/befold.app", installPath: installPath)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: installPath.path)
        #expect(destination == "/Applications/befold.app/Contents/MacOS/befold")
    }

    @Test("管理者権限インストール用のシェルコマンドは rm -f してから ln -s する")
    func administratorInstallShellCommandCreatesSymlink() {
        let command = CLIInstaller.administratorInstallShellCommand(
            target: "/Applications/befold.app/Contents/MacOS/befold",
            destPath: "/usr/local/bin/befold",
            dirPath: "/usr/local/bin"
        )

        #expect(command.contains("mkdir -p '/usr/local/bin'"))
        #expect(command.contains("rm -f '/usr/local/bin/befold'"))
        #expect(command.contains("ln -s '/Applications/befold.app/Contents/MacOS/befold' '/usr/local/bin/befold'"))
    }
}
