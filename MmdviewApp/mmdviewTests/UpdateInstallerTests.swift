import Foundation
@testable import mmdview
import Testing

@Suite
struct UpdateInstallerTests {
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
        let script = UpdateInstaller.updaterScript(
            appInDMG: "/Volumes/mmdview v1.2.0/mmdview.app",
            installedApp: "/Applications/mmdview.app",
            mountPoint: "/Volumes/mmdview v1.2.0",
            dmgPath: "/tmp/mmdview-update.dmg",
            pid: 12345
        )

        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("kill -0 12345"))
        #expect(script.contains(#"rm -rf '/Applications/mmdview.app'"#))
        #expect(script.contains(#"cp -R '/Volumes/mmdview v1.2.0/mmdview.app' '/Applications/mmdview.app'"#))
        #expect(script.contains(#"hdiutil detach '/Volumes/mmdview v1.2.0' -force"#))
        #expect(script.contains(#"rm -f '/tmp/mmdview-update.dmg'"#))
        #expect(script.contains(#"xattr -dr com.apple.quarantine '/Applications/mmdview.app'"#))
        #expect(script.contains(#"open '/Applications/mmdview.app'"#))
        #expect(script.contains(#"rm -f "$0""#))
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
            pid: 12345
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
            pid: 12345
        )

        #expect(script.contains(#"'/Volumes/it'\''s mine/mmdview.app'"#))
    }
}
