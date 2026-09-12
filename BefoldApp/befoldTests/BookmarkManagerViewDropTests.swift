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
