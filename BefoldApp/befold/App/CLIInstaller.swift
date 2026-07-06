import AppKit
import Foundation

enum CLIInstallError: Error, Equatable {
    case writeFailed(String)
}

/// PATH に `befold` コマンドをインストールする(VSCode の `code` コマンド相当)。
enum CLIInstaller {
    /// `open -a` 経由でアプリを起動するシムスクリプトの内容を生成する。
    static func shimScriptContents(bundlePath: String) -> String {
        let shebang = "#!/bin/bash"
        let command = #"exec open -a "\#(bundlePath)" "$@""#
        return "\(shebang)\n\(command)\n"
    }

    /// `installPath` にシムスクリプトを書き込む。書き込み権限がない場合は
    /// 管理者権限(AppleScript `with administrator privileges`)での書き込みにフォールバックする。
    static func install(bundlePath: String, installPath: URL) -> Result<Void, CLIInstallError> {
        let contents = shimScriptContents(bundlePath: bundlePath)
        if writeDirectly(contents: contents, to: installPath) {
            return .success(())
        }
        if writeWithAdministratorPrivileges(contents: contents, to: installPath) {
            return .success(())
        }
        return .failure(.writeFailed(installPath.path))
    }

    private static func writeDirectly(contents: String, to url: URL) -> Bool {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static func writeWithAdministratorPrivileges(contents: String, to url: URL) -> Bool {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try contents.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let destPath = url.path
        let dirPath = url.deletingLastPathComponent().path
        let shellCmd = "mkdir -p \\\"\(dirPath)\\\" && cp \\\"\(tempURL.path)\\\" \\\"\(destPath)\\\" && chmod 755 \\\"\(destPath)\\\""
        let script = "do shell script \"\(shellCmd)\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)
        return errorDict == nil
    }
}
