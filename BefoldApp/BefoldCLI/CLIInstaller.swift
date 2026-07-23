import Darwin
import Foundation

public enum CLIInstallError: Error, Equatable, Sendable {
    case writeFailed(String)
}

public enum CLIInstaller {
    public static let defaultInstallPath = URL(fileURLWithPath: "/usr/local/bin/befold")

    public static func targetExecutablePath(bundlePath: String) -> String {
        "\(bundlePath)/Contents/MacOS/befold-cli"
    }

    public static func install(bundlePath: String, installPath: URL) -> Result<Void, CLIInstallError> {
        let target = targetExecutablePath(bundlePath: bundlePath)
        if writeDirectly(target: target, to: installPath) {
            return .success(())
        }
        if writeWithAdministratorPrivileges(target: target, to: installPath) {
            return .success(())
        }
        return .failure(.writeFailed(installPath.path))
    }

    public static func writeDirectly(target: String, to url: URL) -> Bool {
        let fileManager = FileManager.default
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        do {
            try fileManager.createSymbolicLink(atPath: tempURL.path, withDestinationPath: target)
        } catch {
            return false
        }
        defer { try? fileManager.removeItem(at: tempURL) }

        return rename(tempURL.path, url.path) == 0
    }

    private static func writeWithAdministratorPrivileges(target: String, to url: URL) -> Bool {
        let destPath = url.path
        let dirPath = url.deletingLastPathComponent().path
        let shellCmd = administratorInstallShellCommand(target: target, destPath: destPath, dirPath: dirPath)
        let script = "do shell script \"\(appleScriptQuoted(shellCmd))\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)
        return errorDict == nil
    }

    public static func administratorInstallShellCommand(target: String, destPath: String, dirPath: String) -> String {
        let tempPath = "\(dirPath)/.\(URL(fileURLWithPath: destPath).lastPathComponent).\(UUID().uuidString)"
        return """
        mkdir -p \(dirPath.shellQuoted) && \
        ln -s \(target.shellQuoted) \(tempPath.shellQuoted) && \
        mv -f \(tempPath.shellQuoted) \(destPath.shellQuoted)
        """
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
