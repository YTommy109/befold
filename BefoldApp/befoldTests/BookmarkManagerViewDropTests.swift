import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// Finder からのドロップ経路のうち、SwiftUI の `.onDrop` より内側
/// (`NSItemProvider` → URL → モデル → ストア)を、実際の provider で通す。
/// ドラッグそのものは自動化できないため、受理の判定と非同期の着地をここで固定する。
@Suite
@MainActor
struct BookmarkManagerViewDropTests {
    private let note = URL(fileURLWithPath: "/mock/docs/note.md")

    private func makeView(store: BookmarkStore, onChange: @escaping @MainActor () -> Void = {}) -> BookmarkManagerView {
        let reader = InMemoryFileReader(files: [note.path: "# note"])
        let model = BookmarkManagerModel(store: store, open: { _ in }, onChange: onChange, fileReader: reader)
        return BookmarkManagerView(model: model)
    }

    /// 着地は非同期(provider の読み出し + MainActor 外の stat)なので、上限付きで待つ。
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("ファイル URL の provider を落とすと受理され、非同期にブックマークへ追加される")
    func acceptsFileURLProviderAndAddsBookmark() async {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkManagerViewDrop.accept"))
        var changes = 0
        let view = makeView(store: store) { changes += 1 }

        let accepted = view.handleDrop([NSItemProvider(object: note as NSURL)], into: [])
        await waitUntil { store.isBookmarked(note) }

        #expect(accepted)
        #expect(store.isBookmarked(note))
        #expect(changes == 1)
    }

    /// Bookmark Editor 内の行ドラッグ(TASK-620.3)。行の provider は `.fileURL` を載せないので、Finder からの
    /// 追加の経路には入らず、並び替え(既存のエントリの移動)になる。集合は変わらないので onChange も無い。
    @Test("パネル内の行を落とすと追加ではなく移動になり、兄弟の直前へ入る")
    func bookmarkRowProviderMovesInsteadOfAdding() async throws {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkManagerViewDrop.reorder"))
        let diagram = URL(fileURLWithPath: "/mock/docs/diagram.mmd")
        store.add(note)
        store.add(diagram)
        store.createFolder(named: "Work", in: [])
        var changes = 0
        let view = makeView(store: store) { changes += 1 }
        let diagramEntry = try #require(store.library().entry(for: diagram))

        let accepted = view.handleDrop([BookmarkManagerView.dragProvider(for: diagramEntry)], into: ["Work"])
        await waitUntil { store.library().entry(for: diagram)?.folder == ["Work"] }

        #expect(accepted)
        #expect(store.library().entry(for: diagram)?.folder == ["Work"])
        #expect(store.bookmarkedURLs().count == 2)
        #expect(changes == 0)

        let noteEntry = try #require(store.library().entry(for: note))
        let reordered = view.handleReorder(
            [BookmarkManagerView.dragProvider(for: noteEntry)], into: ["Work"], before: diagram
        )
        await waitUntil { store.library().children(of: ["Work"]).entries.count == 2 }

        #expect(reordered)
        #expect(store.library().children(of: ["Work"]).entries.map(\.path) == [note.path, diagram.path])
    }

    /// `onInsert` の index はその段のエントリの並びでの位置。末尾(= 件数)と範囲外は兄弟なし(末尾へ)。
    @Test("行間の挿入位置は直後のエントリへ直し、末尾なら兄弟なしにする")
    func insertIndexMapsToFollowingSibling() {
        let entries = [BookmarkEntry(path: "/mock/a.md"), BookmarkEntry(path: "/mock/b.md")]

        #expect(BookmarkManagerView.sibling(at: 0, in: entries)?.path == "/mock/a.md")
        #expect(BookmarkManagerView.sibling(at: 1, in: entries)?.path == "/mock/b.md")
        #expect(BookmarkManagerView.sibling(at: 2, in: entries) == nil)
    }

    /// Finder からのファイル URL を並び替えとして扱うと、追加されずに黙って消える。
    @Test("ファイル URL の provider は並び替えとして受理しない")
    func fileURLProviderIsNotAReorder() {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkManagerViewDrop.notReorder"))
        let view = makeView(store: store)

        #expect(!view.handleReorder([NSItemProvider(object: note as NSURL)], into: [], before: nil))
    }

    @Test("ファイル URL を含まないドロップは受理しない")
    func rejectsProvidersWithoutFileURL() {
        let store = BookmarkStore(defaults: makeIsolatedDefaults(prefix: "BookmarkManagerViewDrop.reject"))
        let view = makeView(store: store)

        let accepted = view.handleDrop([NSItemProvider(object: "plain text" as NSString)], into: [])

        #expect(!accepted)
        #expect(store.bookmarkedURLs().isEmpty)
    }

    @Test("弾いた分があるときだけ 1 行の文言になり、件数と理由を含む")
    func feedbackMentionsCountAndReasons() {
        #expect(BookmarkDropOutcome(added: [note]).feedback == nil)

        let outcome = BookmarkDropOutcome(
            added: [],
            rejected: [
                .init(url: URL(fileURLWithPath: "/mock/tool.exe"), reason: .unsupported),
                .init(url: URL(fileURLWithPath: "/mock/gone.md"), reason: .missing),
            ]
        )
        let text = outcome.feedback ?? ""
        #expect(text.contains("2"))
        #expect(text.contains("tool.exe"))
        #expect(text.contains("gone.md"))
    }
}
