import AppKit
import BefoldCLI
import Foundation

/// GUI アプリ本体(befold.app)をプロセスとして起動する処理を抽象化する。テストで
/// 実プロセス起動を差し替えられるようにするための境界。
public protocol ProcessLaunching: Sendable {
    func launchApp(bundlePath: String) throws -> Int32
}

/// `/usr/bin/open -a <bundlePath>` で befold.app を起動する既定の実装。
public struct DefaultProcessLauncher: ProcessLaunching {
    public init() {}

    public func launchApp(bundlePath: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", bundlePath]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// 既に起動中の befold インスタンスがあればそちらへ転送し、無ければ GUI アプリを新規起動してから
/// 転送する。`befold-cli` 実行ファイルのエントリーポイント(`BefoldCLICommand.run()`)から呼ばれる。
public enum CLIAppLauncher {
    @MainActor
    public static func launch(
        paths: [String],
        options: CLIOpenOptions,
        processLauncher: ProcessLaunching = DefaultProcessLauncher(),
        findRunningInstance: @MainActor () -> NSRunningApplication? = { CLIInstanceRouter.runningInstance() }
    ) -> Never {
        let code = run(
            paths: paths, options: options,
            processLauncher: processLauncher,
            findRunningInstance: findRunningInstance
        )
        exit(code)
    }

    @MainActor
    public static func run(
        paths: [String],
        options: CLIOpenOptions,
        processLauncher: ProcessLaunching = DefaultProcessLauncher(),
        findRunningInstance: @MainActor () -> NSRunningApplication? = { CLIInstanceRouter.runningInstance() },
        forward: @MainActor ([String], CLIOpenOptions, NSRunningApplication) -> Bool = {
            CLIInstanceRouter.forward(paths: $0, options: $1, to: $2)
        },
        resolveBundlePath: () -> String = {
            if let execPath = AppVersion.actualExecutablePath() {
                return AppVersion.bundlePath(fromExecutablePath: execPath)
            }
            return Bundle.main.bundlePath
        },
        pollInterval: TimeInterval = 0.1,
        pollTimeout: TimeInterval = 10,
        writeError: (String) -> Void = {
            FileHandle.standardError.write(Data($0.utf8))
        }
    ) -> Int32 {
        let paths = paths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }

        if let running = findRunningInstance() {
            if paths.isEmpty, options == CLIOpenOptions() {
                running.activate()
                return 0
            }
            return forwardOrReportFailure(paths, options, running, forward, writeError)
        }

        let bundlePath = resolveBundlePath()
        do {
            let status = try processLauncher.launchApp(bundlePath: bundlePath)
            guard status == 0 else { return status }
        } catch {
            writeError("Failed to launch app: \(error)\n")
            return 1
        }

        guard !paths.isEmpty || options != CLIOpenOptions() else { return 0 }

        let deadline = Date().addingTimeInterval(pollTimeout)
        var launched: NSRunningApplication?
        while launched == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            launched = findRunningInstance()
        }
        guard let destination = launched else {
            writeError("Timed out waiting for app to launch.\n")
            return 1
        }
        return forwardOrReportFailure(paths, options, destination, forward, writeError)
    }

    @MainActor
    private static func forwardOrReportFailure(
        _ paths: [String],
        _ options: CLIOpenOptions,
        _ destination: NSRunningApplication,
        _ forward: @MainActor ([String], CLIOpenOptions, NSRunningApplication) -> Bool,
        _ writeError: (String) -> Void
    ) -> Int32 {
        guard forward(paths, options, destination) else {
            writeError("Failed to forward to the running instance.\n")
            return 1
        }
        return 0
    }
}
