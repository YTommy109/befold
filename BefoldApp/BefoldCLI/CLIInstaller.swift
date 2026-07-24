import Darwin
import Foundation

/// `CLIInstaller.install` の失敗結果。
public enum CLIInstallError: Error, Equatable, Sendable {
    case writeFailed(String)
}

/// PATH に `befold` コマンドをインストールする(VSCode の `code` コマンド相当)。
///
/// `/usr/local/bin/befold` はバンドル内の実行ファイルへの symlink として設置する。
/// シムスクリプトのファイルをコピーする方式だと、アプリ本体がアップデートされても
/// 設置済みのシムの中身は追随せず古いロジックのまま残ってしまう
/// (例: 旧バージョンでは `open -a` 経由の別方式だった)。symlink はパス解決を OS に
/// 任せるため、アプリが同一パスへ上書き更新される限り常に最新の実行ファイルを指す。
public enum CLIInstaller {
    /// シムの標準設置先。`installCLI` アクションと起動時の状態チェックの双方で共有する。
    public static let defaultInstallPath = URL(fileURLWithPath: "/usr/local/bin/befold")

    /// symlink の参照先となる、バンドル内の実行ファイルのパスを返す。
    public static func targetExecutablePath(bundlePath: String) -> String {
        "\(bundlePath)/Contents/MacOS/befold-cli"
    }

    /// `installPath` にバンドル内実行ファイルへの symlink を作成する。書き込み権限がない場合は
    /// 管理者権限(AppleScript `with administrator privileges`)での作成にフォールバックする。
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

    /// symlink をアトミックに設置する: 同一ディレクトリの一時パスへ symlink を作成してから、
    /// リネームで置き換える。作成が失敗しても既存の設置内容(旧シム等)には触れない
    /// (先に既存を削除してから新規作成すると、途中失敗時にシムが消滅してしまうため)。
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

        // FileManager.replaceItemAt/moveItem are built for document-style files
        // (metadata/xattr preservation, existence checks) and behave unpredictably
        // with symlinks (including dangling ones). `rename(2)` atomically replaces
        // the directory entry itself, regardless of what it currently points to.
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

    /// 管理者権限で実行するシェルコマンドの組み立て。同一ディレクトリの一時パスに symlink を
    /// 作成してから `mv -f`(同一ボリューム上ではアトミックな rename)で置き換える。
    /// `rm -f` してから `ln -s` する方式だと、symlink 作成が失敗した際に既存の設置内容が
    /// 消えたまま復元できないため採らない。
    public static func administratorInstallShellCommand(target: String, destPath: String, dirPath: String) -> String {
        let tempPath = "\(dirPath)/.\(URL(fileURLWithPath: destPath).lastPathComponent).\(UUID().uuidString)"
        return """
        mkdir -p \(dirPath.shellQuoted) && \
        ln -s \(target.shellQuoted) \(tempPath.shellQuoted) && \
        mv -f \(tempPath.shellQuoted) \(destPath.shellQuoted)
        """
    }

    /// AppleScript の文字列リテラル向けにバックスラッシュとダブルクォートをエスケープする。
    private static func appleScriptQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
