import AppKit
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
    /// テスト対象の呼び出し口。各テストは「変える引数だけ」を指定する。
    /// stderr は毎回テスト側で受け取れるよう、常に writeError を差し替えて収集する。
    @MainActor
    private func runLauncher(
        paths: [String] = ["/tmp/test.mmd"],
        options: CLIOpenOptions = CLIOpenOptions(),
        processLauncher: ProcessLaunching = MockProcessLauncher(status: 0),
        findRunningInstance: @MainActor () -> NSRunningApplication? = { NSRunningApplication.current },
        forward: @MainActor ([String], CLIOpenOptions, NSRunningApplication) async -> Bool = { _, _, _ in true },
        resolveBundlePath: () -> String = { "/Applications/befold.app" },
        pollInterval: TimeInterval = 0.01,
        pollTimeout: TimeInterval = 1
    ) async -> (code: Int32, errorOutput: String) {
        var errorOutput = ""
        let code = await CLIAppLauncher.run(
            paths: paths, options: options,
            processLauncher: processLauncher,
            findRunningInstance: findRunningInstance,
            forward: forward,
            resolveBundlePath: resolveBundlePath,
            pollInterval: pollInterval,
            pollTimeout: pollTimeout,
            writeError: { errorOutput += $0 }
        )
        return (code, errorOutput)
    }

    /// 「1 回目は見つからず、2 回目以降で見つかる」= アプリ起動直後のポーリングを模す
    /// findRunningInstance スタブを作る。
    @MainActor
    private func instanceFoundOnSecondPoll() -> (@MainActor () -> NSRunningApplication?) {
        let mockApp = NSRunningApplication.current
        var callCount = 0
        return {
            callCount += 1
            return callCount >= 2 ? mockApp : nil
        }
    }

    @Test("既存インスタンスがあり引数なしなら activate して 0 を返す")
    @MainActor
    func activatesExistingInstanceWithNoPaths() async {
        let result = await runLauncher(
            paths: [],
            forward: { _, _, _ in
                Issue.record("forward should not be called")
                return false
            }
        )

        #expect(result.code == 0)
    }

    @Test("既存インスタンスがありパスありなら forward して結果を返す")
    @MainActor
    func forwardsToExistingInstance() async {
        var forwardedPaths: [String] = []

        let result = await runLauncher(
            forward: { paths, _, _ in
                forwardedPaths = paths
                return true
            }
        )

        #expect(result.code == 0)
        #expect(forwardedPaths.count == 1)
    }

    @Test("既存インスタンスへの forward が失敗したら 1 を返し stderr へ診断メッセージを出力する")
    @MainActor
    func forwardFailureReturnsOneAndWritesStderrMessage() async {
        let result = await runLauncher(forward: { _, _, _ in false })

        #expect(result.code == 1)
        #expect(result.errorOutput.contains("Failed to forward to the running instance."))
    }

    @Test("既存インスタンスなしでアプリ起動に成功しパスなしなら 0 を返す")
    @MainActor
    func launchSucceedsWithNoPaths() async {
        let result = await runLauncher(paths: [], findRunningInstance: { nil })

        #expect(result.code == 0)
    }

    @Test("アプリ起動が非ゼロ終了コードなら そのコードを返し stderr へ診断メッセージを出力する")
    @MainActor
    func launchNonZeroExitReturnsStatusAndWritesStderrMessage() async {
        let result = await runLauncher(
            processLauncher: MockProcessLauncher(status: 42),
            findRunningInstance: { nil }
        )

        #expect(result.code == 42)
        #expect(result.errorOutput.contains("Failed to launch app"))
        #expect(result.errorOutput.contains("/Applications/befold.app"))
        #expect(result.errorOutput.contains("42"))
    }

    @Test("アプリ起動が例外を投げたら 1 を返す")
    @MainActor
    func launchThrowingReturnsOne() async {
        let result = await runLauncher(
            processLauncher: MockProcessLauncher(shouldThrow: true),
            findRunningInstance: { nil }
        )

        #expect(result.code == 1)
    }

    @Test("アプリ起動後にインスタンスが見つかればパスを forward する")
    @MainActor
    func launchAndForwardSucceeds() async {
        var forwardedPaths: [String] = []

        let result = await runLauncher(
            findRunningInstance: instanceFoundOnSecondPoll(),
            forward: { paths, _, _ in
                forwardedPaths = paths
                return true
            }
        )

        #expect(result.code == 0)
        #expect(forwardedPaths.count == 1)
    }

    @Test("アプリ起動後、パスなしでも表示オプション指定ありなら forward する")
    @MainActor
    func launchWithNoPathsButNonDefaultOptionsForwards() async {
        var forwardCalled = false
        var forwardedOptions = CLIOpenOptions()

        let result = await runLauncher(
            paths: [], options: CLIOpenOptions(showHiddenFiles: true),
            findRunningInstance: instanceFoundOnSecondPoll(),
            forward: { _, options, _ in
                forwardCalled = true
                forwardedOptions = options
                return true
            }
        )

        #expect(result.code == 0)
        #expect(forwardCalled)
        #expect(forwardedOptions == CLIOpenOptions(showHiddenFiles: true))
    }

    @Test("アプリ起動後の forward 失敗時にも stderr へ診断メッセージを出力する")
    @MainActor
    func launchAndForwardFailureWritesStderrMessage() async {
        let result = await runLauncher(
            findRunningInstance: instanceFoundOnSecondPoll(),
            forward: { _, _, _ in false }
        )

        #expect(result.errorOutput.contains("Failed to forward to the running instance."))
    }

    @Test("アプリ起動後にインスタンスが見つからずタイムアウトしたら 1 を返す")
    @MainActor
    func launchAndForwardTimesOut() async {
        let result = await runLauncher(
            findRunningInstance: { nil },
            pollTimeout: 0.05
        )

        #expect(result.code == 1)
    }

    /// CLIRequestForwarderTests と同じ方針(実際の DistributedNotificationCenter は使わず
    /// post/ACK 待ち受けを差し替える)で、CLIAppLauncher.run から実際の
    /// CLIRequestForwarder.forward 実装を呼び出し、ACK 受信後ただちに exit(0) することを検証する。
    @Test("実際の forward 実装を通しても、ACK 受信後ただちに exit(0) する")
    @MainActor
    func realForwardReceivesAckAndExitsPromptly() async {
        var activateCount = 0

        let result = await runLauncher(
            forward: { paths, options, destination in
                await CLIRequestForwarder.forward(
                    paths: paths, options: options, to: destination,
                    post: { _, _ in },
                    makeAckWaiter: { _ in StubAckWaiter(ackOnWait: 1) },
                    activate: { activateCount += 1 }
                )
            }
        )

        #expect(result.code == 0)
        #expect(activateCount == 1)
    }
}
