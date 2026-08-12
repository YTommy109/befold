@testable import befold
import BefoldKit
import Foundation
import Testing

/// Tab による入力欄の補完(`completePath()`)を検証する。共通接頭辞までの伸長、
/// 1 件のときのディレクトリ / ファイルの書き分け、fuzzy モードでの無反応を固定する。
@Suite
@MainActor
struct QuickOpenModelTabCompletionTests: QuickOpenModelTestCase {
    @Test("Tab は候補の共通接頭辞まで補完する")
    func tabCompletesCommonPrefix() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold"), url("/dev/before")]
        let model = await makeModel(environment)
        model.queryText = "/dev/b"
        await model.waitForPendingWork()

        await model.completePath()

        // befold と before の共通接頭辞は "befo"
        #expect(model.queryText == "/dev/befo")
    }

    @Test("候補が1件のディレクトリなら次の階層へ進む")
    func tabDescendsIntoSingleDirectory() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold")]
        environment.directories = ["/dev/befold"]
        let model = await makeModel(environment)
        model.queryText = "/dev/be"
        await model.waitForPendingWork()

        await model.completePath()

        #expect(model.queryText == "/dev/befold/")
    }

    @Test("候補が1件のファイルなら名前まで補完してスラッシュは付けない")
    func tabCompletesSingleFileWithoutSlash() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/notes.md")]
        let model = await makeModel(environment)
        model.queryText = "/dev/no"
        await model.waitForPendingWork()

        await model.completePath()

        #expect(model.queryText == "/dev/notes.md")
    }

    @Test("fuzzy モードでは Tab は何もしない")
    func tabDoesNothingInFuzzyMode() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md")]
        let model = await makeModel(environment)
        model.queryText = "alp"
        await model.waitForPendingWork()

        await model.completePath()

        #expect(model.queryText == "alp")
    }
}
