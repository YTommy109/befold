import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct PathListDefaultsTests {
    private let defaults = makeIsolatedDefaults(prefix: "PathListDefaultsTests")

    private func makeList(limit: Int? = nil) -> PathListDefaults {
        PathListDefaults(defaults: defaults, key: "PathListDefaultsTestsKey", limit: limit)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/PathListDefaultsTests/\(name)")
    }

    @Test("未保存なら空配列で hasStoredValue は false")
    func startsEmpty() {
        let list = makeList()
        #expect(list.paths.isEmpty)
        #expect(list.hasStoredValue == false)
    }

    @Test("appendIfAbsent は末尾に追加し、重複追加では順序を変えない")
    func appendIfAbsentIsIdempotent() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        list.appendIfAbsent(url("b"))
        list.appendIfAbsent(url("a"))
        #expect(list.paths == [url("a").normalizedPathKey, url("b").normalizedPathKey])
        #expect(list.hasStoredValue)
    }

    @Test("moveToFront は既存要素を先頭へ移す")
    func moveToFrontReordersExisting() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        list.appendIfAbsent(url("b"))
        list.moveToFront(url("b"))
        #expect(list.paths == [url("b").normalizedPathKey, url("a").normalizedPathKey])
    }

    @Test("moveToFront は未登録の要素を先頭に追加する")
    func moveToFrontInsertsUnknown() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        list.moveToFront(url("z"))
        #expect(list.paths.first == url("z").normalizedPathKey)
        #expect(list.paths.count == 2)
    }

    @Test("remove は該当パスだけを取り除く")
    func removeDropsMatchingPath() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        list.appendIfAbsent(url("b"))
        list.remove(url("a"))
        #expect(list.paths == [url("b").normalizedPathKey])
        list.remove(url("missing"))
        #expect(list.paths == [url("b").normalizedPathKey])
    }

    @Test("contains は正規化パスで判定する")
    func containsUsesNormalizedKey() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        #expect(list.contains(url("a")))
        #expect(list.contains(url("b")) == false)
    }

    @Test("toggle は登録状態を反転させる")
    func toggleFlipsMembership() {
        let list = makeList()
        list.toggle(url("a"))
        #expect(list.contains(url("a")))
        list.toggle(url("a"))
        #expect(list.contains(url("a")) == false)
    }

    @Test("replace は位置を保ったまま旧パスを新パスへ置き換える")
    func replaceKeepsPosition() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        list.appendIfAbsent(url("b"))
        list.replace(url("a"), with: url("c"))
        #expect(list.paths == [url("c").normalizedPathKey, url("b").normalizedPathKey])
    }

    @Test("replace は未登録なら何もしない")
    func replaceIgnoresUnknown() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        list.replace(url("missing"), with: url("c"))
        #expect(list.paths == [url("a").normalizedPathKey])
    }

    @Test("limit を超えた分は書き込みのたびに末尾から捨てられる")
    func limitTruncatesOnWrite() {
        let list = makeList(limit: 2)
        list.moveToFront(url("a"))
        list.moveToFront(url("b"))
        list.moveToFront(url("c"))
        #expect(list.paths == [url("c").normalizedPathKey, url("b").normalizedPathKey])
    }

    @Test("replaceAll は空配列でも保存済みとして記録される")
    func replaceAllStoresEmptyArray() {
        let list = makeList()
        list.replaceAll(with: [])
        #expect(list.paths.isEmpty)
        #expect(list.hasStoredValue)
    }

    @Test("urls は保存順の URL を返す")
    func urlsPreserveOrder() {
        let list = makeList()
        list.appendIfAbsent(url("a"))
        list.appendIfAbsent(url("b"))
        #expect(list.urls == [url("a"), url("b")].map { URL(fileURLWithPath: $0.normalizedPathKey) })
    }
}
