import Foundation

/// CLI サブコマンドの実行結果。`exitCode == 0` なら stdout、それ以外は stderr へ `message` を出力する。
public struct CLICommandResult: Equatable, Sendable {
    public let message: String
    public let exitCode: Int32

    public init(message: String, exitCode: Int32) {
        self.message = message
        self.exitCode = exitCode
    }
}

/// `CLICommandResult` を stdout/stderr へ出力する。終了コードの決定・プロセス終了は
/// 呼び出し側(`BefoldCLICommand.run()`)が担う(--check/--bookmark 併用時に
/// 複数件の結果をまとめて出力してから終了コードを決めるため)。
public enum CLICommandResultPrinter {
    public static func print(_ result: CLICommandResult) {
        if result.exitCode == 0 {
            Swift.print(result.message)
        } else {
            FileHandle.standardError.write(Data((result.message + "\n").utf8))
        }
    }
}
