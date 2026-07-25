import Foundation

/// git コマンド実行を一元化する薄い Process ラッパ。
/// git 未インストール・実行失敗・非 0 終了はすべて nil に倒す。
/// git を呼ぶ全機能(パス解決・将来のブランチ/差分)の共通土台。
struct GitCommandRunner: Sendable {
    func run(_ args: [String], in workingDirectory: URL? = nil) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    func runString(_ args: [String], in workingDirectory: URL? = nil) -> String? {
        guard let data = run(args, in: workingDirectory) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
