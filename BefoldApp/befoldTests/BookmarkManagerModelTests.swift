@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 管理パネルのモデル。ストアへの書き込みと、集合が変わったときだけ `onChange` が呼ばれることを固定する。
@Suite
@MainActor
struct BookmarkManagerModelTests {
    private let note = URL(fileURLWithPath: "/mock/docs/note.md")
    private let diagram = URL(fileURLWithPath: "/mock/docs/diagram.mmd")

    private func makeStore() -> BookmarkStore {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkManagerModelTests"))
        store.add(note)
        store.add(diagram)
        return store
    }

    @Test("remove でストアから消え、一覧が更新され、onChange が 1 回呼ばれる")
    func removeWritesThroughAndNotifiesOnce() {
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: { changes += 1 })

        model.remove(note)

        #expect(!store.isBookmarked(note))
        #expect(store.isBookmarked(diagram))
        #expect(model.entries.map(\.url) == [diagram])
        #expect(changes == 1)
    }

    /// 未登録のパスは書き込みも通知も起こさない(窓のツールバーを無駄に再同期しない)。
    @Test("未登録のパスの remove は何もせず onChange も呼ばない")
    func removeIgnoresUnknownPath() {
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: { changes += 1 })

        model.remove(URL(fileURLWithPath: "/mock/unknown.md"))

        #expect(store.bookmarkedURLs() == [note, diagram])
        #expect(changes == 0)
    }

    /// 別名は集合を変えないので窓側に伝える必要が無い。
    @Test("setAlias は一覧に反映されるが onChange は呼ばない")
    func setAliasRefreshesWithoutNotifying() {
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: { changes += 1 })

        model.setAlias("Zulu", for: note)

        #expect(model.entries.map(\.displayName) == ["diagram.mmd", "Zulu"])
        #expect(changes == 0)
    }

    /// パネルの外(窓の ⌘D・欠落の一括削除)で変わった分は refresh で拾う。
    @Test("refresh はストアの現在値を取り直す")
    func refreshPicksUpExternalChanges() {
        let store = makeStore()
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: {})
        store.remove(diagram)

        model.refresh()

        #expect(model.entries.map(\.url) == [note])
    }

    /// フォルダーの操作は集合を変えないので窓側に伝えない。スナップショットだけが追随する。
    @Test("フォルダーの作成・移動・改名・削除は onChange を呼ばず、一覧に反映される")
    func folderOperationsRefreshWithoutNotifying() {
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: { changes += 1 })

        #expect(model.createFolder(named: "Work", in: []))
        #expect(!model.createFolder(named: "Work", in: []))
        #expect(model.move(note, to: ["Work"]))
        #expect(model.renameFolder(at: ["Work"], to: "Office"))
        #expect(model.children(of: ["Office"]).entries.map(\.url) == [note])
        model.setExpanded(false, for: ["Office"])
        #expect(model.library.folders == [BookmarkFolder(path: ["Office"], isExpanded: false)])
        #expect(model.deleteFolder(at: ["Office"]))

        #expect(model.children(of: []).entries.map(\.url) == [diagram, note])
        #expect(store.library().folders.isEmpty)
        #expect(changes == 0)
    }

    // MARK: - ドロップ(536.3)

    private static func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    /// 受け入れ規則を 1 回のドロップで全部通す: 対応ファイルとフォルダーは追加、存在しない・
    /// 非対応は理由付きで弾く、登録済みは追加も弾きもしない。追加があるので onChange は 1 回。
    @Test("ドロップ: 存在する対応ファイルとフォルダーを追加し、存在しない・非対応は理由付きで弾く")
    func addDroppedAppliesAcceptanceRules() async {
        let reader = InMemoryFileReader(
            files: ["/mock/new.md": "# new", "/mock/tool.exe": "x"], directories: ["/mock/dir"]
        )
        let store = makeStore()
        var changes = 0
        let model = BookmarkManagerModel(
            store: store, open: { _ in }, onChange: { changes += 1 }, fileReader: reader
        )

        await model.addDropped(
            [
                Self.url("/mock/new.md"),
                Self.url("/mock/dir"),
                Self.url("/mock/tool.exe"),
                Self.url("/mock/missing.md"),
                note,
                Self.url("/mock/new.md"),
            ],
            into: []
        )

        #expect(store.isBookmarked(Self.url("/mock/new.md")))
        #expect(store.isBookmarked(Self.url("/mock/dir")))
        #expect(!store.isBookmarked(Self.url("/mock/tool.exe")))
        #expect(model.lastDrop?.added == [Self.url("/mock/new.md"), Self.url("/mock/dir")])
        #expect(model.lastDrop?.rejected == [
            .init(url: Self.url("/mock/tool.exe"), reason: .unsupported),
            .init(url: Self.url("/mock/missing.md"), reason: .missing),
        ])
        #expect(changes == 1)
    }

    @Test("フォルダー行へ落とすとそのフォルダーの直下に入り、追加ゼロのドロップは onChange を呼ばない")
    func addDroppedIntoFolderAndNoChangeWhenNothingAdded() async {
        let reader = InMemoryFileReader(files: ["/mock/new.md": "# new"])
        let store = makeStore()
        store.createFolder(named: "Work", in: [])
        var changes = 0
        let model = BookmarkManagerModel(
            store: store, open: { _ in }, onChange: { changes += 1 }, fileReader: reader
        )

        await model.addDropped([Self.url("/mock/new.md")], into: ["Work"])
        #expect(store.library().entry(for: Self.url("/mock/new.md"))?.folder == ["Work"])
        #expect(changes == 1)

        await model.addDropped([note, Self.url("/mock/missing.md")], into: ["Work"])
        #expect(model.lastDrop?.added.isEmpty == true)
        #expect(model.lastDrop?.rejected.map(\.reason) == [.missing])
        #expect(changes == 1)
    }
}
