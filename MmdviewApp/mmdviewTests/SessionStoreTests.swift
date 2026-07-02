import Foundation
import Testing
@testable import mmdview

@Suite
@MainActor
struct SessionStoreTests {
    /// テストごとに独立した UserDefaults スイートを用意する。
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SessionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func savedURLsIsEmptyInitially() {
        let store = SessionStore(defaults: makeDefaults())

        #expect(store.savedURLs().isEmpty)
    }

    @Test
    func noteOpenedPersistsURLAcrossInstances() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        SessionStore(defaults: defaults).noteOpened(url)

        let restored = SessionStore(defaults: defaults).savedURLs()
        #expect(restored == [url])
    }

    @Test
    func noteOpenedPreservesOrderWithoutDuplicates() {
        let defaults = makeDefaults()
        let first = URL(fileURLWithPath: "/tmp/first.mmd")
        let second = URL(fileURLWithPath: "/tmp/second.md")
        let store = SessionStore(defaults: defaults)

        store.noteOpened(first)
        store.noteOpened(second)
        store.noteOpened(first)

        #expect(SessionStore(defaults: defaults).savedURLs() == [first, second])
    }

    @Test
    func noteClosedRemovesURL() {
        let defaults = makeDefaults()
        let first = URL(fileURLWithPath: "/tmp/first.mmd")
        let second = URL(fileURLWithPath: "/tmp/second.md")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(first)
        store.noteOpened(second)

        store.noteClosed(first)

        #expect(SessionStore(defaults: defaults).savedURLs() == [second])
    }

    @Test("freeze 後の noteClosed は無視される(アプリ終了時にリストが空にならない)")
    func noteClosedAfterFreezeIsIgnored() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(url)

        store.freeze()
        store.noteClosed(url)

        #expect(SessionStore(defaults: defaults).savedURLs() == [url])
    }
}
