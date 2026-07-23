@testable import befold
@testable import BefoldCLI
import Foundation
import Testing

@Suite
struct CLIInstallerTests {
    @Test("シムの参照先は bundle 内の実行ファイルである")
    func targetExecutablePathPointsIntoBundle() {
        let target = CLIInstaller.targetExecutablePath(bundlePath: "/Applications/befold.app")

        #expect(target == "/Applications/befold.app/Contents/MacOS/befold-cli")
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
        #expect(destination == "/Applications/befold.app/Contents/MacOS/befold-cli")
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
            withDestinationPath: "/Applications/befold-old.app/Contents/MacOS/befold-cli"
        )

        let result = CLIInstaller.install(bundlePath: "/Applications/befold.app", installPath: installPath)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: installPath.path)
        #expect(destination == "/Applications/befold.app/Contents/MacOS/befold-cli")
    }

    @Test("symlink 作成に失敗した場合、既存の設置内容は変更されずに残る")
    func writeDirectlyPreservesExistingShimWhenSymlinkCreationFails() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        let legacyContents = "#!/bin/bash\nexec open -a \"/Applications/befold.app\" \"$@\"\n"
        try legacyContents.write(to: installPath, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tmp.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.url.path) }

        let succeeded = CLIInstaller.writeDirectly(
            target: "/Applications/befold.app/Contents/MacOS/befold-cli", to: installPath
        )

        #expect(!succeeded)
        let attributes = try FileManager.default.attributesOfItem(atPath: installPath.path)
        #expect(attributes[.type] as? FileAttributeType != .typeSymbolicLink)
        let contents = try String(contentsOf: installPath, encoding: .utf8)
        #expect(contents == legacyContents)
    }

    @Test("管理者権限インストール用のシェルコマンドは一時パスに symlink を作成してから mv -f でアトミックに置き換える")
    func administratorInstallShellCommandCreatesSymlinkAtomically() {
        let command = CLIInstaller.administratorInstallShellCommand(
            target: "/Applications/befold.app/Contents/MacOS/befold-cli",
            destPath: "/usr/local/bin/befold",
            dirPath: "/usr/local/bin"
        )

        #expect(command.contains("mkdir -p '/usr/local/bin'"))
        #expect(command.contains("ln -s '/Applications/befold.app/Contents/MacOS/befold-cli' '/usr/local/bin/."))
        #expect(command.contains("&& mv -f '/usr/local/bin/."))
        #expect(command.contains("' '/usr/local/bin/befold'"))
        #expect(!command.contains("rm -f"))
    }
}
