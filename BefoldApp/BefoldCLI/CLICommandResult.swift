import Foundation

public struct CLICommandResult: Equatable, Sendable {
    public let message: String
    public let exitCode: Int32

    public init(message: String, exitCode: Int32) {
        self.message = message
        self.exitCode = exitCode
    }
}

public enum CLICommandResultPrinter {
    public static func print(_ result: CLICommandResult) {
        if result.exitCode == 0 {
            Swift.print(result.message)
        } else {
            FileHandle.standardError.write(Data((result.message + "\n").utf8))
        }
    }
}
