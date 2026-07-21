import Foundation

enum CLIInstallError: Error, Equatable {
    case writeFailed(String)
}

/// PATH に `befold` コマンドをインストールする(VSCode の `code` コマンド相当)。
///
/// `/usr/local/bin/befold` はバンドル内の実行ファイルへの symlink として設置する。
/// シムスクリプトのファイルをコピーする方式だと、アプリ本体がアップデートされても
/// 設置済みのシムの中身は追随せず古いロジックのまま残ってしまう
/// (例: 旧バージョンでは `open -a` 経由の別方式だった)。symlink はパス解決を OS に
/// 任せるため、アプリが同一パスへ上書き更新される限り常に最新の実行ファイルを指す。
enum CLIInstaller {
    /// シムの標準設置先。`installCLI` アクションと起動時の状態チェックの双方で共有する。
    static let defaultInstallPath = URL(fileURLWithPath: "/usr/local/bin/befold")

    /// symlink の参照先となる、バンドル内の実行ファイルのパスを返す。
    static func targetExecutablePath(bundlePath: String) -> String {
        "\(bundlePath)/Contents/MacOS/befold"
    }

    /// `installPath` にバンドル内実行ファイルへの symlink を作成する。書き込み権限がない場合は
    /// 管理者権限(AppleScript `with administrator privileges`)での作成にフォールバックする。
    static func install(bundlePath: String, installPath: URL) -> Result<Void, CLIInstallError> {
        let target = targetExecutablePath(bundlePath: bundlePath)
        if writeDirectly(target: target, to: installPath) {
            return .success(())
        }
        if writeWithAdministratorPrivileges(target: target, to: installPath) {
            return .success(())
        }
        return .failure(.writeFailed(installPath.path))
    }

    private static func writeDirectly(target: String, to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
            return true
        } catch {
            return false
        }
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

    /// 管理者権限で実行するシェルコマンドの組み立て。既存の実体ファイル/symlink を
    /// 削除してから symlink を作成する(`ln -s` は既存パスがあると失敗するため)。
    static func administratorInstallShellCommand(target: String, destPath: String, dirPath: String) -> String {
        """
        mkdir -p \(dirPath.shellQuoted) && \
        rm -f \(destPath.shellQuoted) && \
        ln -s \(target.shellQuoted) \(destPath.shellQuoted)
        """
    }

    /// AppleScript の文字列リテラル向けにバックスラッシュとダブルクォートをエスケープする。
    private static func appleScriptQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
