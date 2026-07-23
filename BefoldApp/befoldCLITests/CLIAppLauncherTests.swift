import AppKit
@testable import befold_cli
@testable import BefoldCLI
import Foundation
import Testing

struct MockProcessLauncher: ProcessLaunching {
    var status: Int32
    var shouldThrow: Bool

    init(status: Int32 = 0, shouldThrow: Bool = false) {
        self.status = status
        self.shouldThrow = shouldThrow
    }

    func launchApp(bundlePath: String) throws -> Int32 {
        if shouldThrow {
            throw NSError(
                domain: "test", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "mock error"]
            )
        }
        return status
    }
}

@Suite
struct CLIAppLauncherTests {
    @Test("既存インスタンスがあり引数なしなら activate して 0 を返す")
    @MainActor
    func activatesExistingInstanceWithNoPaths() {
        var activated = false
        let mockApp = NSRunningApplication.current

        let code = CLIAppLauncher.run(
            paths: [], options: CLIOpenOptions(),
            findRunningInstance: { mockApp },
            forward: { _, _, _ in
                Issue.record("forward should not be called")
                return false
            }
        )

        _ = activated
        #expect(code == 0)
    }

    @Test("既存インスタンスがありパスありなら forward して結果を返す")
    @MainActor
    func forwardsToExistingInstance() {
        let mockApp = NSRunningApplication.current
        var forwardedPaths: [String] = []

        let code = CLIAppLauncher.run(
            paths: ["/tmp/test.mmd"], options: CLIOpenOptions(),
            findRunningInstance: { mockApp },
            forward: { paths, _, _ in
                forwardedPaths = paths
                return true
            }
        )

        #expect(code == 0)
        #expect(forwardedPaths.count == 1)
    }

    @Test("既存インスタンスへの forward が失敗したら 1 を返す")
    @MainActor
    func forwardFailureReturnsOne() {
        let mockApp = NSRunningApplication.current

        let code = CLIAppLauncher.run(
            paths: ["/tmp/test.mmd"], options: CLIOpenOptions(),
            findRunningInstance: { mockApp },
            forward: { _, _, _ in false }
        )

        #expect(code == 1)
    }

    @Test("既存インスタンスなしでアプリ起動に成功しパスなしなら 0 を返す")
    @MainActor
    func launchSucceedsWithNoPaths() {
        let launcher = MockProcessLauncher(status: 0)

        let code = CLIAppLauncher.run(
            paths: [], options: CLIOpenOptions(),
            processLauncher: launcher,
            findRunningInstance: { nil },
            resolveBundlePath: { "/Applications/befold.app" }
        )

        #expect(code == 0)
    }

    @Test("アプリ起動が非ゼロ終了コードなら そのコードを返す")
    @MainActor
    func launchNonZeroExitReturnsStatus() {
        let launcher = MockProcessLauncher(status: 42)

        let code = CLIAppLauncher.run(
            paths: ["/tmp/test.mmd"], options: CLIOpenOptions(),
            processLauncher: launcher,
            findRunningInstance: { nil },
            resolveBundlePath: { "/Applications/befold.app" }
        )

        #expect(code == 42)
    }

    @Test("アプリ起動が例外を投げたら 1 を返す")
    @MainActor
    func launchThrowingReturnsOne() {
        let launcher = MockProcessLauncher(shouldThrow: true)

        let code = CLIAppLauncher.run(
            paths: ["/tmp/test.mmd"], options: CLIOpenOptions(),
            processLauncher: launcher,
            findRunningInstance: { nil },
            resolveBundlePath: { "/Applications/befold.app" }
        )

        #expect(code == 1)
    }

    @Test(
        "アプリ起動後にインスタンスが見つかればパスを forward する"
    )
    @MainActor
    func launchAndForwardSucceeds() {
        let launcher = MockProcessLauncher(status: 0)
        let mockApp = NSRunningApplication.current
        var callCount = 0
        var forwardedPaths: [String] = []

        let code = CLIAppLauncher.run(
            paths: ["/tmp/test.mmd"], options: CLIOpenOptions(),
            processLauncher: launcher,
            findRunningInstance: {
                callCount += 1
                return callCount >= 2 ? mockApp : nil
            },
            forward: { paths, _, _ in
                forwardedPaths = paths
                return true
            },
            resolveBundlePath: { "/Applications/befold.app" },
            pollInterval: 0.01,
            pollTimeout: 1
        )

        #expect(code == 0)
        #expect(forwardedPaths.count == 1)
    }

    @Test("アプリ起動後にインスタンスが見つからずタイムアウトしたら 1 を返す")
    @MainActor
    func launchAndForwardTimesOut() {
        let launcher = MockProcessLauncher(status: 0)

        let code = CLIAppLauncher.run(
            paths: ["/tmp/test.mmd"], options: CLIOpenOptions(),
            processLauncher: launcher,
            findRunningInstance: { nil },
            resolveBundlePath: { "/Applications/befold.app" },
            pollInterval: 0.01,
            pollTimeout: 0.05
        )

        #expect(code == 1)
    }
}
