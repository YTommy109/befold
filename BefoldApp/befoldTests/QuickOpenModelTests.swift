@testable import befold
import BefoldKit
import Foundation
import Testing

/// `open()` が呼ばれるまで `wait()` を止める関門。候補集合の到着タイミングを
/// スリープに頼らず決定的に操るために使う。
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for continuation in pending {
            continuation.resume()
        }
    }
}

/// ウィンドウにもパネルにも依存させず、「入力を与えると期待した候補になる」
/// 「決定時に注入したクロージャが正しい URL で呼ばれる」だけを検証する。
@Suite
@MainActor
struct QuickOpenModelTests {
    /// ファイルシステムを持たない差し替え環境。
    private final class StubEnvironment: QuickOpenEnvironment {
        var baseDirectory: URL?
        var includingHiddenFiles = false
        var candidates: [QuickOpenCandidate] = []
        var isTruncated = false
        /// ディレクトリ URL の正規化パス → その中身。
        var entries: [String: [URL]] = [:]
        var directories: Set<String> = []
        var resolvedFile: [String: URL] = [:]

        /// 候補集合の到着を遅らせるための関門。nil なら即時に返す。
        var candidateSetGate: (@Sendable () async -> Void)?

        func candidateSet() async -> QuickOpenCandidateSet {
            await candidateSetGate?()
            return QuickOpenCandidateSet(candidates: candidates, isTruncated: isTruncated)
        }

        func directoryEntries(in directory: URL) async -> [URL]? {
            entries[directory.normalizedPathKey] ?? []
        }

        func isDirectory(_ url: URL) async -> Bool {
            directories.contains(url.normalizedPathKey)
        }

        func resolveFileToOpen(at url: URL) async -> URL? {
            await isDirectory(url) ? resolvedFile[url.normalizedPathKey] : url
        }
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    private func candidate(_ path: String, _ display: String, _ origin: QuickOpenCandidate.Origin = .indexed)
        -> QuickOpenCandidate
    {
        QuickOpenCandidate(url: url(path), displayPath: display, origin: origin)
    }

    /// 候補集合の到着と絞り込みが落ち着いた状態のモデルを返す。
    private func makeModel(
        _ environment: StubEnvironment,
        onOpen: @escaping (URL) -> Void = { _ in }
    ) async -> QuickOpenModel {
        let model = QuickOpenModel(environment: environment, onOpen: onOpen)
        await model.waitForPendingWork()
        return model
    }

    // MARK: - 候補集合の非同期到着

    @Test("候補集合の到着前でも init は返り、入力を受け付ける")
    func modelIsUsableBeforeCandidateSetArrives() async {
        let environment = StubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md", .recent)]
        let released = AsyncGate()
        environment.candidateSetGate = { await released.wait() }

        // 候補集合を止めたまま init する。ここで返ってくること自体が「パネル即時表示」の根拠。
        let model = QuickOpenModel(environment: environment, onOpen: { _ in })
        #expect(model.candidates.isEmpty)

        // 到着前でも入力は受け付ける(空集合に対する絞り込みが走るだけ)。
        model.queryText = "alp"
        #expect(model.candidates.isEmpty)

        await released.open()
        await model.waitForPendingWork()

        // 到着後、その時点の入力に対する絞り込み結果へ差し替わる。
        #expect(model.candidates.map(\.displayPath) == ["alpha.md"])
    }

    @Test("候補集合の到着より後の入力が優先される(古い世代の結果で上書きしない)")
    func laterQueryWinsOverArrivingCandidateSet() async {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/alpha.md", "alpha.md", .recent),
            candidate("/repo/zulu.md", "zulu.md", .recent),
        ]
        let released = AsyncGate()
        environment.candidateSetGate = { await released.wait() }

        let model = QuickOpenModel(environment: environment, onOpen: { _ in })
        model.queryText = "zul"
        await released.open()
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.displayPath) == ["zulu.md"])
    }

    @Test("パスモードの列挙はキーストロークの延長では走らない")
    func pathModeEnumerationDoesNotRunInline() async {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold")]
        let model = await makeModel(environment)

        model.queryText = "/dev/be"

        // setter から戻った時点ではまだ列挙結果が入っていない = 呼び出し元を待たせていない。
        #expect(model.candidates.isEmpty)

        await model.waitForPendingWork()
        #expect(model.candidates.map(\.url) == [url("/dev/befold")])
    }

    // MARK: - 空入力

    @Test("空入力では索引に載っている履歴のみを出す")
    func emptyQueryShowsRecentsOnly() async {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/r.md", "r.md", .recent),
            candidate("/repo/m.md", "m.md", .bookmark),
            candidate("/repo/i.md", "i.md", .indexed),
        ]
        let model = await makeModel(environment)

        // 空入力では recent(時計)のみ。bookmark・indexed は羅列しない。
        #expect(model.candidates.map(\.displayPath) == ["r.md"])
    }

    // MARK: - fuzzy 検索

    @Test("fuzzy 入力では候補を絞り込む")
    func fuzzyQueryFilters() async {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/alpha.md", "alpha.md"),
            candidate("/repo/zzz.md", "zzz.md"),
        ]
        let model = await makeModel(environment)

        model.queryText = "alp"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.displayPath) == ["alpha.md"])
    }

    @Test("候補ゼロは一致なしとして扱いエラーにしない")
    func noMatchesIsNotAnError() async {
        let environment = StubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md")]
        let model = await makeModel(environment)

        model.queryText = "qqq"
        await model.waitForPendingWork()

        #expect(model.candidates.isEmpty)
        #expect(model.showsNoMatches)
    }

    @Test("候補の打ち切りは表示に伝わる")
    func truncationIsSurfaced() async {
        let environment = StubEnvironment()
        environment.candidates = [candidate("/repo/a.md", "a.md")]
        environment.isTruncated = true
        let model = await makeModel(environment)

        model.queryText = "a"
        await model.waitForPendingWork()

        #expect(model.showsTruncationNotice)
    }

    // MARK: - パスモード

    @Test("パス入力は親ディレクトリの中身を末尾断片で前方一致絞り込みする")
    func pathModeFiltersByPrefix() async {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold"), url("/dev/beta"), url("/dev/other")]
        let model = await makeModel(environment)

        model.queryText = "/dev/be"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/dev/befold"), url("/dev/beta")])
    }

    @Test("末尾がスラッシュなら中身を全件出す")
    func trailingSlashListsEverything() async {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/a"), url("/dev/b")]
        let model = await makeModel(environment)

        model.queryText = "/dev/"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/dev/a"), url("/dev/b")])
    }

    @Test("前方一致は大文字小文字を無視する")
    func prefixMatchIsCaseInsensitive() async {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/Befold")]
        let model = await makeModel(environment)

        model.queryText = "/dev/be"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/dev/Befold")])
    }

    @Test("相対パスは開いているファイルのディレクトリを基準に解決する")
    func relativePathResolvesAgainstBaseDirectory() async {
        let environment = StubEnvironment()
        environment.baseDirectory = url("/repo/docs")
        environment.entries["/repo/docs"] = [url("/repo/docs/guide.md")]
        let model = await makeModel(environment)

        model.queryText = "./gu"
        await model.waitForPendingWork()

        #expect(model.candidates.map(\.url) == [url("/repo/docs/guide.md")])
    }

    @Test("親ディレクトリが存在しなければ一致なしになる")
    func missingParentDirectoryYieldsNoMatches() async {
        let environment = StubEnvironment()
        let model = await makeModel(environment)

        model.queryText = "/nope/x"
        await model.waitForPendingWork()

        #expect(model.candidates.isEmpty)
        #expect(model.showsNoMatches)
    }

    @Test("パスモードでは隠しファイルを設定に従って出し分ける")
    func pathModeHonorsHiddenFilesSetting() async {
        let environment = StubEnvironment()
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

    // MARK: - Tab 補完

    @Test("Tab は候補の共通接頭辞まで補完する")
    func tabCompletesCommonPrefix() async {
        let environment = StubEnvironment()
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
        let environment = StubEnvironment()
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
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/notes.md")]
        let model = await makeModel(environment)
        model.queryText = "/dev/no"
        await model.waitForPendingWork()

        await model.completePath()

        #expect(model.queryText == "/dev/notes.md")
    }

    @Test("fuzzy モードでは Tab は何もしない")
    func tabDoesNothingInFuzzyMode() async {
        let environment = StubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md")]
        let model = await makeModel(environment)
        model.queryText = "alp"
        await model.waitForPendingWork()

        await model.completePath()

        #expect(model.queryText == "alp")
    }

    // MARK: - 選択と決定

    @Test("選択は上下に動き、両端で止まる")
    func selectionMovesWithinBounds() async {
        let environment = StubEnvironment()
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
        let environment = StubEnvironment()
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
        let environment = StubEnvironment()
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
        let environment = StubEnvironment()
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
        let environment = StubEnvironment()
        var opened: [URL] = []
        let model = await makeModel(environment) { opened.append($0) }
        model.queryText = "/nope/x"
        await model.waitForPendingWork()

        await model.commitSelection()

        #expect(opened.isEmpty)
    }

    @Test("中身が空のディレクトリを決定しても何も開かない")
    func commitOnEmptyDirectoryDoesNothing() async {
        let environment = StubEnvironment()
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
        let environment = StubEnvironment()
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
