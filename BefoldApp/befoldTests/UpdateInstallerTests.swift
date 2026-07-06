import Foundation
@testable import mmdview
import Testing

@Suite
struct UpdateInstallerTests {
    /// 全テスト共通の代表的なパスでスクリプトを生成する。
    private func makeScript() -> String {
        UpdateInstaller.updaterScript(
            appInDMG: "/Volumes/mmdview v1.2.0/mmdview.app",
            installedApp: "/Applications/mmdview.app",
            mountPoint: "/Volumes/mmdview v1.2.0",
            dmgPath: "/tmp/mmdview-update.dmg",
            pid: 12345,
            logPath: "/Users/dev/Library/Logs/mmdview-updater.log"
        )
    }

    @Test
    func installedAppURLAcceptsAppBundle() {
        let bundle = URL(fileURLWithPath: "/Applications/mmdview.app")
        #expect(UpdateInstaller.installedAppURL(bundleURL: bundle) == bundle)
    }

    @Test
    func installedAppURLRejectsDevBuildDirectory() {
        let devDir = URL(fileURLWithPath: "/Users/dev/mmdview/.build/debug")
        #expect(UpdateInstaller.installedAppURL(bundleURL: devDir) == nil)
    }

    @Test
    func updaterScriptContainsAllSteps() {
        let script = makeScript()

        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("kill -0 12345"))
        #expect(script.contains(#"cp -R '/Volumes/mmdview v1.2.0/mmdview.app' '/Applications/mmdview.app.update'"#))
        #expect(script.contains(#"mv '/Applications/mmdview.app.update' '/Applications/mmdview.app'"#))
        #expect(script.contains(#"hdiutil detach '/Volumes/mmdview v1.2.0' -force"#))
        #expect(script.contains(#"rm -f '/tmp/mmdview-update.dmg'"#))
        #expect(script.contains(#"xattr -dr com.apple.quarantine '/Applications/mmdview.app'"#))
        #expect(script.contains(#"open '/Applications/mmdview.app'"#))
        #expect(script.contains(#"rm -f "$0""#))
    }

    /// 全出力がログファイルへリダイレクトされ、失敗が事後調査できること。
    @Test
    func updaterScriptRedirectsOutputToLogFile() {
        let script = makeScript()

        #expect(script.contains(#"exec >> '/Users/dev/Library/Logs/mmdview-updater.log' 2>&1"#))
    }

    /// 新アプリはまずステージングへコピーし、成功してから旧アプリを削除・入れ替えること。
    /// (旧実装は先に旧アプリを rm -rf しており、コピー失敗でアプリが消滅していた)
    @Test
    func updaterScriptCopiesToStagingBeforeRemovingInstalledApp() throws {
        let script = makeScript()

        let copy = try #require(
            script.range(of: #"cp -R '/Volumes/mmdview v1.2.0/mmdview.app'"#)
        )
        let removeInstalled = try #require(
            // 末尾のクォートまで含めることでステージング(….app.update)の削除とは区別する
            script.range(of: #"rm -rf '/Applications/mmdview.app'"#)
        )
        #expect(copy.lowerBound < removeInstalled.lowerBound)
    }

    /// コピー失敗時は旧アプリを削除せず(if の成功側でのみ削除)、
    /// ステージングを片付けたうえで現行アプリを開き直すこと。
    @Test
    func updaterScriptKeepsInstalledAppWhenCopyFails() throws {
        let script = makeScript()

        #expect(script.contains("if /bin/cp -R"))
        let elseRange = try #require(script.range(of: "else"))
        let removeInstalled = try #require(script.range(of: #"rm -rf '/Applications/mmdview.app'"#))
        // 旧アプリの削除は if の成功側(else より前)だけにあること
        #expect(removeInstalled.lowerBound < elseRange.lowerBound)
        let afterElse = elseRange.upperBound ..< script.endIndex
        #expect(script.range(of: #"rm -rf '/Applications/mmdview.app'"#, range: afterElse) == nil)
        // open は分岐の外(常に実行)にあること
        let open = try #require(script.range(of: #"open '/Applications/mmdview.app'"#))
        let fiRange = try #require(script.range(of: "\nfi"))
        #expect(fiRange.upperBound < open.lowerBound)
    }

    /// `"`・`$`・バッククォートを含むパスでも、シングルクォート化により
    /// シェルに解釈されずリテラルとして安全に埋め込まれることを検証する。
    @Test
    func updaterScriptSafelyQuotesSpecialCharacters() {
        let evil = #"/Volumes/we"ir$d`whoami`/mmdview.app"#
        let script = UpdateInstaller.updaterScript(
            appInDMG: evil,
            installedApp: evil,
            mountPoint: evil,
            dmgPath: evil,
            pid: 12345,
            logPath: evil
        )

        // パス全体がシングルクォートで囲まれ、内部の特殊文字はそのまま残る。
        #expect(script.contains(#"'/Volumes/we"ir$d`whoami`/mmdview.app'"#))
        // 危険な文字がクォート外に露出していないこと（ダブルクォート補間の名残がない）。
        #expect(!script.contains(#""/Volumes/we"#))
    }

    /// パスにシングルクォートが含まれる場合でも `'\''` 方式で正しくエスケープされ、
    /// クォートが閉じたまま後続がシェルに解釈されないことを検証する。
    @Test
    func updaterScriptEscapesSingleQuoteInPath() {
        let path = "/Volumes/it's mine/mmdview.app"
        let script = UpdateInstaller.updaterScript(
            appInDMG: path,
            installedApp: path,
            mountPoint: path,
            dmgPath: path,
            pid: 12345,
            logPath: path
        )

        #expect(script.contains(#"'/Volumes/it'\''s mine/mmdview.app'"#))
    }
}
