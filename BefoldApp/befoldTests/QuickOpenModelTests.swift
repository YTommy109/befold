@testable import befold
import BefoldKit
import Foundation
import Testing

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

        func candidateSet() -> QuickOpenCandidateSet {
            QuickOpenCandidateSet(candidates: candidates, isTruncated: isTruncated)
        }

        func directoryEntries(in directory: URL) -> [URL] {
            entries[directory.normalizedPathKey] ?? []
        }

        func isDirectory(_ url: URL) -> Bool {
            directories.contains(url.normalizedPathKey)
        }

        func resolveFileToOpen(at url: URL) -> URL? {
            isDirectory(url) ? resolvedFile[url.normalizedPathKey] : url
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

    private func makeModel(
        _ environment: StubEnvironment,
        onOpen: @escaping (URL) -> Void = { _ in }
    ) -> QuickOpenModel {
        QuickOpenModel(environment: environment, onOpen: onOpen)
    }

    // MARK: - 空入力

    @Test("空入力では索引に載っている履歴のみを出す")
    func emptyQueryShowsRecentsOnly() {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/r.md", "r.md", .recent),
            candidate("/repo/m.md", "m.md", .bookmark),
            candidate("/repo/i.md", "i.md", .indexed),
        ]
        let model = makeModel(environment)

        // 空入力では recent(時計)のみ。bookmark・indexed は羅列しない。
        #expect(model.candidates.map(\.displayPath) == ["r.md"])
    }

    // MARK: - fuzzy 検索

    @Test("fuzzy 入力では候補を絞り込む")
    func fuzzyQueryFilters() {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/alpha.md", "alpha.md"),
            candidate("/repo/zzz.md", "zzz.md"),
        ]
        let model = makeModel(environment)

        model.queryText = "alp"

        #expect(model.candidates.map(\.displayPath) == ["alpha.md"])
    }

    @Test("候補ゼロは一致なしとして扱いエラーにしない")
    func noMatchesIsNotAnError() {
        let environment = StubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md")]
        let model = makeModel(environment)

        model.queryText = "qqq"

        #expect(model.candidates.isEmpty)
        #expect(model.showsNoMatches)
    }

    @Test("候補の打ち切りは表示に伝わる")
    func truncationIsSurfaced() {
        let environment = StubEnvironment()
        environment.candidates = [candidate("/repo/a.md", "a.md")]
        environment.isTruncated = true
        let model = makeModel(environment)

        model.queryText = "a"

        #expect(model.showsTruncationNotice)
    }

    // MARK: - パスモード

    @Test("パス入力は親ディレクトリの中身を末尾断片で前方一致絞り込みする")
    func pathModeFiltersByPrefix() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold"), url("/dev/beta"), url("/dev/other")]
        let model = makeModel(environment)

        model.queryText = "/dev/be"

        #expect(model.candidates.map(\.url) == [url("/dev/befold"), url("/dev/beta")])
    }

    @Test("末尾がスラッシュなら中身を全件出す")
    func trailingSlashListsEverything() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/a"), url("/dev/b")]
        let model = makeModel(environment)

        model.queryText = "/dev/"

        #expect(model.candidates.map(\.url) == [url("/dev/a"), url("/dev/b")])
    }

    @Test("前方一致は大文字小文字を無視する")
    func prefixMatchIsCaseInsensitive() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/Befold")]
        let model = makeModel(environment)

        model.queryText = "/dev/be"

        #expect(model.candidates.map(\.url) == [url("/dev/Befold")])
    }

    @Test("相対パスは開いているファイルのディレクトリを基準に解決する")
    func relativePathResolvesAgainstBaseDirectory() {
        let environment = StubEnvironment()
        environment.baseDirectory = url("/repo/docs")
        environment.entries["/repo/docs"] = [url("/repo/docs/guide.md")]
        let model = makeModel(environment)

        model.queryText = "./gu"

        #expect(model.candidates.map(\.url) == [url("/repo/docs/guide.md")])
    }

    @Test("親ディレクトリが存在しなければ一致なしになる")
    func missingParentDirectoryYieldsNoMatches() {
        let environment = StubEnvironment()
        let model = makeModel(environment)

        model.queryText = "/nope/x"

        #expect(model.candidates.isEmpty)
        #expect(model.showsNoMatches)
    }

    @Test("パスモードでは隠しファイルを設定に従って出し分ける")
    func pathModeHonorsHiddenFilesSetting() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/.hidden"), url("/dev/visible")]
        let model = makeModel(environment)

        model.queryText = "/dev/"
        #expect(model.candidates.map(\.url) == [url("/dev/visible")])

        // ドット始まりの断片を打った場合は、設定に関わらず隠しファイルを出す
        model.queryText = "/dev/."
        #expect(model.candidates.map(\.url) == [url("/dev/.hidden")])
    }

    // MARK: - Tab 補完

    @Test("Tab は候補の共通接頭辞まで補完する")
    func tabCompletesCommonPrefix() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold"), url("/dev/before")]
        let model = makeModel(environment)
        model.queryText = "/dev/b"

        model.completePath()

        // befold と before の共通接頭辞は "befo"
        #expect(model.queryText == "/dev/befo")
    }

    @Test("候補が1件のディレクトリなら次の階層へ進む")
    func tabDescendsIntoSingleDirectory() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/befold")]
        environment.directories = ["/dev/befold"]
        let model = makeModel(environment)
        model.queryText = "/dev/be"

        model.completePath()

        #expect(model.queryText == "/dev/befold/")
    }

    @Test("候補が1件のファイルなら名前まで補完してスラッシュは付けない")
    func tabCompletesSingleFileWithoutSlash() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/notes.md")]
        let model = makeModel(environment)
        model.queryText = "/dev/no"

        model.completePath()

        #expect(model.queryText == "/dev/notes.md")
    }

    @Test("fuzzy モードでは Tab は何もしない")
    func tabDoesNothingInFuzzyMode() {
        let environment = StubEnvironment()
        environment.candidates = [candidate("/repo/alpha.md", "alpha.md")]
        let model = makeModel(environment)
        model.queryText = "alp"

        model.completePath()

        #expect(model.queryText == "alp")
    }

    // MARK: - 選択と決定

    @Test("選択は上下に動き、両端で止まる")
    func selectionMovesWithinBounds() {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/a.md", "a.md", .recent),
            candidate("/repo/b.md", "b.md", .recent),
        ]
        let model = makeModel(environment)

        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 1)
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 1)
        model.moveSelection(by: -5)
        #expect(model.selectedIndex == 0)
    }

    @Test("入力が変わると選択は先頭に戻る")
    func selectionResetsOnQueryChange() {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/aa.md", "aa.md", .recent),
            candidate("/repo/ab.md", "ab.md", .recent),
        ]
        let model = makeModel(environment)
        model.moveSelection(by: 1)

        model.queryText = "a"

        #expect(model.selectedIndex == 0)
    }

    @Test("決定は選択中の URL でクロージャを呼ぶ")
    func commitOpensSelectedURL() {
        let environment = StubEnvironment()
        environment.candidates = [
            candidate("/repo/a.md", "a.md", .recent),
            candidate("/repo/b.md", "b.md", .recent),
        ]
        var opened: [URL] = []
        let model = makeModel(environment) { opened.append($0) }
        model.moveSelection(by: 1)

        model.commitSelection()

        #expect(opened == [url("/repo/b.md")])
    }

    @Test("決定対象がディレクトリなら中の1ファイルを開く")
    func commitResolvesDirectoryToFile() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/docs")]
        environment.directories = ["/dev/docs"]
        environment.resolvedFile["/dev/docs"] = url("/dev/docs/index.md")
        var opened: [URL] = []
        let model = makeModel(environment) { opened.append($0) }
        model.queryText = "/dev/do"

        model.commitSelection()

        #expect(opened == [url("/dev/docs/index.md")])
    }

    @Test("開ける対象が無ければ決定は何もしない")
    func commitWithoutCandidateDoesNothing() {
        let environment = StubEnvironment()
        var opened: [URL] = []
        let model = makeModel(environment) { opened.append($0) }
        model.queryText = "/nope/x"

        model.commitSelection()

        #expect(opened.isEmpty)
    }

    @Test("中身が空のディレクトリを決定しても何も開かない")
    func commitOnEmptyDirectoryDoesNothing() {
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/empty")]
        environment.directories = ["/dev/empty"]
        var opened: [URL] = []
        let model = makeModel(environment) { opened.append($0) }
        model.queryText = "/dev/em"

        model.commitSelection()

        #expect(opened.isEmpty)
    }

    @Test("開けない候補で決定しても onOpen を呼ばず候補表示を保つ(パネルは閉じない)")
    func commitOnUnopenableTargetKeepsCandidates() {
        // パネルを閉じるのは onOpen 経由の dismiss だけなので、onOpen が呼ばれない
        // = パネルは閉じない。開けない対象で Enter しても候補一覧が保たれることを固定する。
        let environment = StubEnvironment()
        environment.entries["/dev"] = [url("/dev/empty")]
        environment.directories = ["/dev/empty"] // resolvedFile 未設定 → 解決不能
        var opened: [URL] = []
        let model = makeModel(environment) { opened.append($0) }
        model.queryText = "/dev/em"
        let before = model.candidates.map(\.url)

        model.commitSelection()

        #expect(opened.isEmpty)
        #expect(model.candidates.map(\.url) == before)
        #expect(!model.candidates.isEmpty)
    }
}
