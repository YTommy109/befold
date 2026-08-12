@testable import befold
import BefoldKit
import Foundation
import Testing

/// パス入力(スラッシュを含む入力)での候補列挙を検証する。親ディレクトリの決め方
/// (絶対 / 相対 / 不在)と、末尾断片による前方一致・隠しファイルの出し分けを固定する。
@Suite
@MainActor
struct QuickOpenModelPathModeTests: QuickOpenModelTestCase {
    @Test("パス入力は親ディレクトリの中身を末尾断片で前方一致絞り込みする")
    func pathModeFiltersByPrefix() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold"), url("/dev/beta"), url("/dev/other")]
        let model = await makeModel(environment)

        model.queryText = "/dev/be"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/dev/befold"), url("/dev/beta")])
    }

    @Test("末尾がスラッシュなら中身を全件出す")
    func trailingSlashListsEverything() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/a"), url("/dev/b")]
        let model = await makeModel(environment)

        model.queryText = "/dev/"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/dev/a"), url("/dev/b")])
    }

    @Test("前方一致は大文字小文字を無視する")
    func prefixMatchIsCaseInsensitive() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/Befold")]
        let model = await makeModel(environment)

        model.queryText = "/dev/be"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/dev/Befold")])
    }

    @Test("相対パスは開いているファイルのディレクトリを基準に解決する")
    func relativePathResolvesAgainstBaseDirectory() async {
        let environment = QuickOpenStubEnvironment()
        environment.baseDirectory = url("/repo/docs")
        environment.entries["/repo/docs"] = [url("/repo/docs/guide.md")]
        let model = await makeModel(environment)

        model.queryText = "./gu"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/repo/docs/guide.md")])
    }

    @Test("親ディレクトリが存在しなければ一致なしになる")
    func missingParentDirectoryYieldsNoMatches() async {
        let environment = QuickOpenStubEnvironment()
        let model = await makeModel(environment)

        model.queryText = "/nope/x"
        await model.waitForPendingWork()

        #expect(model.candidates.isEmpty)
        #expect(model.showsNoMatches)
    }

    @Test("パスモードでは隠しファイルを設定に従って出し分ける")
    func pathModeHonorsHiddenFilesSetting() async {
        let environment = QuickOpenStubEnvironment()
        environment.entries["/dev"] = [url("/dev/.hidden"), url("/dev/visible")]
        let model = await makeModel(environment)

        model.queryText = "/dev/"
        await model.waitForPendingWork()
        #expect(model.candidates.map(\.url) == [url("/dev/visible")])

        // ドット始まりの断片を打った場合は、設定に関わらず隠しファイルを出す
        model.queryText = "/dev/."
        await model.waitForPendingWork()
        #expect(model.candidates.map(\.url) == [url("/dev/.hidden")])
    }
}
