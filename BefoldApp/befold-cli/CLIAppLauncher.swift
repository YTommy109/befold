import AppKit
import BefoldCLI
import Foundation

public protocol ProcessLaunching: Sendable {
    func launchApp(bundlePath: String) throws -> Int32
}

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

public enum CLIAppLauncher {
    public static func launch(
        paths: [String],
        options: CLIOpenOptions,
        processLauncher: ProcessLaunching = DefaultProcessLauncher(),
        findRunningInstance: @MainActor () -> NSRunningApplication? = CLIInstanceRouter.runningInstance
    ) -> Never {
        let code = MainActor.assumeIsolated {
            run(
                paths: paths, options: options,
                processLauncher: processLauncher,
                findRunningInstance: findRunningInstance
            )
        }
        exit(code)
    }

    @MainActor
    public static func run(
        paths: [String],
        options: CLIOpenOptions,
        processLauncher: ProcessLaunching = DefaultProcessLauncher(),
        findRunningInstance: @MainActor () -> NSRunningApplication? = CLIInstanceRouter.runningInstance,
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
        pollTimeout: TimeInterval = 10
    ) -> Int32 {
        let paths = paths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }

        if let running = findRunningInstance() {
            if paths.isEmpty, options == CLIOpenOptions() {
                running.activate()
                return 0
            }
            return forward(paths, options, running) ? 0 : 1
        }

        let bundlePath = resolveBundlePath()
        do {
            let status = try processLauncher.launchApp(bundlePath: bundlePath)
            guard status == 0 else { return status }
        } catch {
            FileHandle.standardError.write(
                Data("Failed to launch app: \(error)\n".utf8)
            )
            return 1
        }

        guard !paths.isEmpty else { return 0 }

        let deadline = Date().addingTimeInterval(pollTimeout)
        var launched: NSRunningApplication?
        while launched == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            launched = findRunningInstance()
        }
        guard let destination = launched else {
            FileHandle.standardError.write(
                Data("Timed out waiting for app to launch.\n".utf8)
            )
            return 1
        }
        return forward(paths, options, destination) ? 0 : 1
    }
}
