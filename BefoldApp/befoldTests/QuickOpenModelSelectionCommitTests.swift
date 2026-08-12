@testable import befold
import BefoldKit
import Foundation
import Testing

/// 選択(上下移動・入力変更時のリセット)と決定(`commitSelection()`)を検証する。
/// 決定では、注入したクロージャが正しい URL で呼ばれること、開けない対象では
/// 呼ばれず候補表示が保たれることまでを固定する。
@Suite
@MainActor
struct QuickOpenModelSelectionCommitTests: QuickOpenModelTestCase {
    @Test("選択は上下に動き、両端で止まる")
    func selectionMovesWithinBounds() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [
            candidate("/repo/a.md", "a.md", .recent),
            candidate("/repo/b.md", "b.md", .recent),
        ]
        let model = await makeModel(environment)

        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 1)
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 1)
        model.moveSelection(by: -5)
        #expect(model.selectedIndex == 0)
    }

    @Test("入力が変わると選択は先頭に戻る")
    func selectionResetsOnQueryChange() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [
            candidate("/repo/aa.md", "aa.md", .recent),
            candidate("/repo/ab.md", "ab.md", .recent),
        ]
        let model = await makeModel(environment)
        model.moveSelection(by: 1)

        model.queryText = "a"
        await model.waitForPendingWork()

        #expect(model.selectedIndex == 0)
    }

    @Test("決定は選択中の URL でクロージャを呼ぶ")
    func commitOpensSelectedURL() async {
        let environment = QuickOpenStubEnvironment()
        environment.candidates = [
            candidate("/repo/a.md", "a.md", .recent),
            candidate("/repo/b.md", "b.md", .recent),
        ]
        var opened: [URL] = []
        let model = await makeModel(environment) { opened.append($0) }
        model.moveSelection(by: 1)

        await model.commitSelection()

        #expect(opened == [url("/repo/b.md")])
    }

    @Test("決定対象がディレクトリなら中の1ファイルを開く")
    func commitResolvesDirectoryToFile() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/docs")]
        environment.directories = ["/dev/docs"]
        environment.resolvedFile["/dev/docs"] = url("/dev/docs/index.md")
        var opened: [URL] = []
        let model = await makeModel(environment) { opened.append($0) }
        model.queryText = "/dev/do"
        await model.waitForPendingWork()

        await model.commitSelection()

        #expect(opened == [url("/dev/docs/index.md")])
    }

    @Test("開ける対象が無ければ決定は何もしない")
    func commitWithoutCandidateDoesNothing() async {
        let environment = QuickOpenStubEnvironment()
        var opened: [URL] = []
        let model = await makeModel(environment) { opened.append($0) }
        model.queryText = "/nope/x"
        await model.waitForPendingWork()

        await model.commitSelection()

        #expect(opened.isEmpty)
    }

    @Test("中身が空のディレクトリを決定しても何も開かない")
    func commitOnEmptyDirectoryDoesNothing() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/empty")]
        environment.directories = ["/dev/empty"]
        var opened: [URL] = []
        let model = await makeModel(environment) { opened.append($0) }
        model.queryText = "/dev/em"
        await model.waitForPendingWork()

        await model.commitSelection()

        #expect(opened.isEmpty)
    }

    @Test("開けない候補で決定しても onOpen を呼ばず候補表示を保つ(パネルは閉じない)")
    func commitOnUnopenableTargetKeepsCandidates() async {
        // パネルを閉じるのは onOpen 経由の dismiss だけなので、onOpen が呼ばれない
        // = パネルは閉じない。開けない対象で Enter しても候補一覧が保たれることを固定する。
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/empty")]
        environment.directories = ["/dev/empty"] // resolvedFile 未設定 → 解決不能
        var opened: [URL] = []
        let model = await makeModel(environment) { opened.append($0) }
        model.queryText = "/dev/em"
        await model.waitForPendingWork()
        let before = model.candidates.map(\.url)

        await model.commitSelection()

        #expect(opened.isEmpty)
        #expect(model.candidates.map(\.url) == before)
        #expect(!model.candidates.isEmpty)
    }
}
