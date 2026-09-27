@testable import befold
import Foundation
import Testing

/// `withObservationTracking` の onChange は Sendable なクロージャなので、
/// 発火をローカル変数ではなく参照で受ける。
private final class ObservationFlag: @unchecked Sendable {
    private(set) var isRaised = false
    private(set) var count = 0

    func raise() {
        isRaised = true
        count += 1
    }
}

/// 「同じ結果なら作り直さない」ことを固定する(TASK-532)。
///
/// 同一ディレクトリの再列挙は、ウィンドウ生成直後(`ViewerWindowController` の
/// `refreshFileList`)とキーウィンドウ化のたび(`windowDidBecomeKey`)に走る。
///
/// **測るのは `previewTarget` を読む観測が汚れたか**。`entries` を読む観測では測れない
/// ——Swift の Observation は Equatable な値の同値代入では観測を汚さないので、
/// ガードの有無に関わらず発火 0 になり、テストが空振りする(実測で確認済み)。
/// 実際に汚れるのは Equatable でない `FileListModel.entryIndex` の作り直しを経由する
/// 側だけで、それを読むのが `previewTarget`(ViewerContentView・ツールバー同期)。
@Suite
@MainActor
struct SidebarIdenticalListingTests {
    private let directory = URL(fileURLWithPath: "/tmp/befold-task-532")

    private func makeModel() -> FileListModel {
        FileListModel(currentDirectory: directory, entries: [], selection: nil)
    }

    private func makePresenter(_ model: FileListModel) -> SidebarTreePresenter {
        SidebarTreePresenter(fileListModel: model, childrenLister: { _, _, _ in nil })
    }

    private func listing(_ names: [String], didFail: Bool = false) -> DirectoryListing {
        DirectoryListing(
            rootChildren: names.map {
                FileListEntry(url: directory.appendingPathComponent($0), kind: .file)
            },
            didFailEnumeration: didFail
        )
    }

    /// `body` の実行で、`read` が読む観測値のいずれかが汚れたか。
    private func observesChange(during body: () -> Void, reading read: @escaping () -> Void) -> Bool {
        let flag = ObservationFlag()
        withObservationTracking(read) { flag.raise() }
        body()
        return flag.isRaised
    }

    @Test("同じ列挙結果を 2 回反映しても、提示対象の観測は汚れない")
    func identicalListingDoesNotInvalidatePreviewTarget() {
        let model = makeModel()
        let presenter = makePresenter(model)
        presenter.applyRows(listing(["a.md", "b.md"]), for: directory)

        let dirtied = observesChange {
            presenter.applyRows(listing(["a.md", "b.md"]), for: directory)
        } reading: { [model] in
            _ = model.previewTarget
        }

        #expect(!dirtied)
    }

    /// 「反映を飛ばしすぎていない」ことの手すり。ガードの有無に関わらず通る
    /// (＝これ自体は修正の担保ではない)。反映ごと落とす実装へ壊したときに落ちる。
    @Test("同じ列挙結果では索引の引き当ても保たれる")
    func identicalListingKeepsEntryIndex() throws {
        let model = makeModel()
        let presenter = makePresenter(model)
        presenter.applyRows(listing(["a.md"]), for: directory)
        let key = directory.appendingPathComponent("a.md").normalizedPathKey
        try #require(model.entry(forPathKey: key) != nil)

        presenter.applyRows(listing(["a.md"]), for: directory)

        #expect(model.entry(forPathKey: key) != nil)
    }

    /// 列挙に失敗した状態でも同じこと。失敗フラグが同じなら取り直しても汚さない。
    @Test("列挙失敗が続いている間も、同じ結果なら汚れない")
    func identicalFailedListingDoesNotInvalidate() {
        let model = makeModel()
        let presenter = makePresenter(model)
        presenter.applyRows(listing(["a.md"], didFail: true), for: directory)

        let dirtied = observesChange {
            presenter.applyRows(listing(["a.md"], didFail: true), for: directory)
        } reading: { [model] in
            _ = model.previewTarget
        }

        #expect(!dirtied)
        #expect(model.didFailListing)
    }

    /// AC#4 の裏。表示内容が実際に変わる 4 つの形で、従来どおり反映されること。
    /// (d) の disclosure だけが `FileListEntry` の合成 `==` に依存しており、
    /// 等値を「url だけ」へ弱めた瞬間に落ちる。
    @Test("行・ディレクトリ・列挙失敗・開閉三角のいずれかが変われば反映される")
    func changedListingIsApplied() {
        let cases: [(String, (SidebarTreePresenter, FileListModel) -> Void)] = [
            ("行が増える", { presenter, _ in
                presenter.applyRows(listing(["a.md", "b.md"]), for: directory)
            }),
            ("ディレクトリが違う", { presenter, _ in
                let other = directory.appendingPathComponent("sub")
                presenter.applyRows(listing(["a.md"]), for: other)
            }),
            ("列挙失敗の有無が違う", { presenter, _ in
                presenter.applyRows(listing(["a.md"], didFail: true), for: directory)
            }),
            ("開閉三角が付く", { presenter, model in
                let rows = [
                    FileListEntry(url: directory.appendingPathComponent("a.md"), kind: .file)
                        .disclosing(.collapsed),
                ]
                model.setEntries(rows, for: directory, didFailEnumeration: false)
                presenter.applyRows(listing(["a.md"]), for: directory)
            }),
        ]

        for (label, mutate) in cases {
            let model = makeModel()
            let presenter = makePresenter(model)
            presenter.applyRows(listing(["a.md"]), for: directory)

            let dirtied = observesChange {
                mutate(presenter, model)
            } reading: { [model] in
                _ = model.previewTarget
                _ = model.entries
                _ = model.entriesDirectory
                _ = model.didFailListing
            }

            #expect(dirtied, "\(label): 変化したのに反映されていない")
        }
    }

    /// ガードの条件から `hasLoadedEntries` を落とすと、空のフォルダを開いたときに
    /// 「まだ届いていない」のままになり、空状態の文言(TASK-410 / TASK-530)が出なくなる。
    @Test("初回が空の一覧でも、届いたこと自体は記録される")
    func firstEmptyListingStillMarksLoaded() {
        let model = makeModel()
        let presenter = makePresenter(model)
        #expect(!model.hasLoadedEntries)

        presenter.applyRows(listing([]), for: directory)

        #expect(model.hasLoadedEntries)
    }

    /// 同値の git 状態は書き込み点(`setGitStatus`)で弾く。観測が汚れないことはここで、
    /// 代入そのものが起きないことは `identicalGitStatusKeepsStorage` で固定する。
    @Test("同じ git 状態を新しい発行順序で反映しても、観測は汚れない")
    func identicalGitStatusDoesNotInvalidate() {
        let model = makeModel()
        let status = SidebarGitStatus(
            repositoryRootKey: directory.normalizedPathKey,
            statuses: [:]
        )
        model.applyGitStatus(status, for: directory, sequence: 1)

        let dirtied = observesChange {
            model.applyGitStatus(status, for: directory, sequence: 2)
        } reading: { [model] in
            _ = model.gitStatus
        }

        #expect(!dirtied)
    }

    /// 同値の取り直しでは**代入しない**(TASK-646)。代入すると辞書のストレージが入れ替わり、
    /// `SidebarTreePresenter.revealChangedFolders` の「適用済みと同じか」の比較が同一ストレージの
    /// 早期 return に乗らず、`applyRows` のたびに全量比較になる。値の比較では測れないので、
    /// 辞書の参照(Darwin の Dictionary は 1 語のストレージ参照)で同一性を見る。
    @Test("同じ git 状態を別に作り直して反映しても、保持している値は差し替わらない")
    func identicalGitStatusKeepsStorage() throws {
        let model = makeModel()
        let key = directory.appendingPathComponent("a.md").normalizedPathKey
        func make() -> SidebarGitStatus {
            SidebarGitStatus(
                repositoryRootKey: directory.normalizedPathKey,
                statuses: [key: GitFileStatus(indexChange: nil, worktreeChange: .modified)]
            )
        }
        model.applyGitStatus(make(), for: directory, sequence: 1)
        let before = try #require(model.gitStatus).files

        model.applyGitStatus(make(), for: directory, sequence: 2)
        let after = try #require(model.gitStatus).files

        let isSameStorage = unsafeBitCast(before, to: AnyObject.self) === unsafeBitCast(after, to: AnyObject.self)
        #expect(isSameStorage)
    }

    /// AC#3 の計測。Cmd+クリックで新規タブを開くと、同一ディレクトリの列挙は
    /// 最大 3 回走る(新規タブの生成直後 / 新規タブのキー化 / 元タブへ戻したときのキー化)。
    /// **列挙の回数はこの修正では減らない**——減るのは一覧の反映(索引の作り直しと
    /// 提示対象の無効化)の回数だけ。
    @Test("同一ディレクトリを 3 回列挙しても、一覧の反映は 1 回に畳まれる")
    func repeatedListingsCollapseToSingleApplication() {
        let model = makeModel()
        let presenter = makePresenter(model)
        let invalidations = ObservationFlag()
        for _ in 0 ..< 3 {
            withObservationTracking { [model] in
                _ = model.previewTarget
            } onChange: {
                invalidations.raise()
            }
            presenter.applyRows(listing(["a.md", "b.md"]), for: directory)
        }

        // 初回の 1 回だけ。2 回目・3 回目は同じ結果なので観測を汚さない。
        #expect(invalidations.count == 1)
    }
}
