import AppKit
@testable import befold
import Foundation
import Testing

/// AppDelegate.decideLaunchAction() の分岐を検証する。
/// 実際の DistributedNotificationCenter / NSApplication.run() には依存せず、
/// 「既存インスタンスの有無」「転送成否」「パスの有無」の組み合わせだけを直接渡して判定する。
@Suite
@MainActor
struct AppDelegateLaunchTests {
    @Test("既存インスタンスが無ければ、パスの有無にかかわらず新規インスタンスとして起動する")
    func launchesAsNewInstanceWhenNoRunningInstance() {
        #expect(
            AppDelegate.decideLaunchAction(paths: [], runningInstance: nil, forwardSucceeded: false)
                == .launchAsNewInstance
        )
        #expect(
            AppDelegate.decideLaunchAction(paths: ["a.md"], runningInstance: nil, forwardSucceeded: false)
                == .launchAsNewInstance
        )
    }

    @Test("既存インスタンスへの転送に成功したら exitSuccess")
    func exitsSuccessfullyWhenForwardSucceeds() {
        #expect(
            AppDelegate.decideLaunchAction(
                paths: ["a.md"], runningInstance: NSRunningApplication.current, forwardSucceeded: true
            ) == .exitSuccess
        )
    }

    @Test("パス無し起動で転送に失敗した場合、新規インスタンスとしてフォールバックする(TASK-78)")
    func fallsBackToNewInstanceWhenPathlessForwardFails() {
        #expect(
            AppDelegate.decideLaunchAction(
                paths: [], runningInstance: NSRunningApplication.current, forwardSucceeded: false
            ) == .launchAsNewInstance
        )
    }

    @Test("パス指定ありの起動で転送に失敗した場合はエラー終了する(TASK-73.7の二重起動を再発させない)")
    func exitsWithErrorWhenForwardFailsWithPaths() {
        #expect(
            AppDelegate.decideLaunchAction(
                paths: ["a.md"], runningInstance: NSRunningApplication.current, forwardSucceeded: false
            ) == .exitWithForwardError
        )
    }
}
