import Foundation
@testable import mmdview
import Testing

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

    @Test
    func savedLayoutIsNilInitially() {
        let store = SessionStore(defaults: makeDefaults())

        #expect(store.savedLayout() == nil)
    }

    @Test
    func saveLayoutRoundTripsAcrossInstances() {
        let defaults = makeDefaults()
        let layout = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: ["/tmp/a.mmd", "/tmp/b.md"], selectedPath: "/tmp/b.md"),
            SessionLayout.TabGroup(paths: ["/tmp/c.mmd"], selectedPath: "/tmp/c.mmd"),
        ])

        SessionStore(defaults: defaults).saveLayout(layout)

        #expect(SessionStore(defaults: defaults).savedLayout() == layout)
    }

    @Test("壊れた JSON は nil を返しフォールバックに切り替わる")
    func savedLayoutReturnsNilForCorruptData() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "SessionLayout")

        #expect(SessionStore(defaults: defaults).savedLayout() == nil)
    }

    @Test("空のレイアウトは nil 扱いでフォールバックに切り替わる")
    func savedLayoutReturnsNilForEmptyGroups() {
        let defaults = makeDefaults()
        SessionStore(defaults: defaults).saveLayout(SessionLayout(groups: []))

        #expect(SessionStore(defaults: defaults).savedLayout() == nil)
    }

    @Test
    func noteActivatedPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/active.mmd")

        SessionStore(defaults: defaults).noteActivated(url)

        #expect(SessionStore(defaults: defaults).savedActivePath() == url.normalizedPathKey)
    }

    @Test("アクティブファイルを閉じたら記録もクリアされる")
    func noteClosedClearsMatchingActivePath() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/active.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(url)
        store.noteActivated(url)

        store.noteClosed(url)

        #expect(store.savedActivePath() == nil)
    }

    @Test("別ファイルを閉じてもアクティブ記録は残る")
    func noteClosedKeepsUnrelatedActivePath() {
        let defaults = makeDefaults()
        let active = URL(fileURLWithPath: "/tmp/active.mmd")
        let other = URL(fileURLWithPath: "/tmp/other.md")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(active)
        store.noteOpened(other)
        store.noteActivated(active)

        store.noteClosed(other)

        #expect(store.savedActivePath() == active.normalizedPathKey)
    }

    @Test("freeze 後の noteClosed はアクティブ記録もクリアしない")
    func noteClosedAfterFreezeKeepsActivePath() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/active.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(url)
        store.noteActivated(url)

        store.freeze()
        store.noteClosed(url)

        #expect(store.savedActivePath() == url.normalizedPathKey)
    }

    @Test("freeze 後の noteActivated は無視される(終了処理中のキー変更で確定値が上書きされない)")
    func noteActivatedAfterFreezeIsIgnored() {
        let defaults = makeDefaults()
        let active = URL(fileURLWithPath: "/tmp/active.mmd")
        let other = URL(fileURLWithPath: "/tmp/other.md")
        let store = SessionStore(defaults: defaults)
        store.noteActivated(active)

        store.freeze()
        store.noteActivated(other)

        #expect(store.savedActivePath() == active.normalizedPathKey)
    }

    @Test("rename でアクティブ記録が新パスに移る")
    func noteRenamedMigratesActivePath() {
        let defaults = makeDefaults()
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteActivated(old)

        store.noteRenamed(from: old, to: new)

        #expect(store.savedActivePath() == new.normalizedPathKey)
    }

    @Test("無関係なアクティブ記録は rename で変わらない")
    func noteRenamedKeepsUnrelatedActivePath() {
        let defaults = makeDefaults()
        let active = URL(fileURLWithPath: "/tmp/active.mmd")
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteActivated(active)

        store.noteRenamed(from: old, to: new)

        #expect(store.savedActivePath() == active.normalizedPathKey)
    }

    @Test("rename で保存済みレイアウト内のパスと選択タブが書き換わる")
    func noteRenamedRewritesLayoutPaths() {
        let defaults = makeDefaults()
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let other = "/tmp/other.md"
        let store = SessionStore(defaults: defaults)
        store.saveLayout(SessionLayout(groups: [
            SessionLayout.TabGroup(paths: [other, old.normalizedPathKey], selectedPath: old.normalizedPathKey),
        ]))

        store.noteRenamed(from: old, to: new)

        let expected = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: [other, new.normalizedPathKey], selectedPath: new.normalizedPathKey),
        ])
        #expect(store.savedLayout() == expected)
    }
}
