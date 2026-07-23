import BefoldCLI
import Foundation

/// `/usr/local/bin/befold` の設置状態。
enum CLIShimStatus: Equatable {
    /// 何も設置されていない。
    case notInstalled
    /// 現在のバンドル実行ファイルを指す symlink が設置済み。
    case upToDate
    /// 実体ファイル(旧バージョンの静的シムスクリプト)が設置されている。
    case legacyFile
    /// symlink だが、参照先が現在のバンドル実行ファイルと一致しない(ダングリング含む)。
    case staleSymlink
}

/// `CLIInstaller` が設置したシムの状態を読み取り専用で判定する。
/// 書き込み(再インストール)は一切行わない。
enum CLIShimInspector {
    static func status(bundlePath: String, installPath: URL) -> CLIShimStatus {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: installPath.path) else {
            return .notInstalled
        }
        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return .legacyFile
        }
        let expectedTarget = CLIInstaller.targetExecutablePath(bundlePath: bundlePath)
        let actualTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: installPath.path)
        return actualTarget == expectedTarget ? .upToDate : .staleSymlink
    }
}
