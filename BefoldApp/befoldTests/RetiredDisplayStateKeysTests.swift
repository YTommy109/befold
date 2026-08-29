@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 永続化をやめた表示状態（スクロール位置・表示モード）の旧キーが、既存ユーザーの
/// defaults から確実に消えることを検証する（TASK-565 / CLAUDE.md「UserDefaults キーの
/// 廃止・改名」）。移行はしない——永続化そのものをやめたので移行先が無い。
@Suite
@MainActor
struct RetiredDisplayStateKeysTests {
    private let markdown = URL(fileURLWithPath: "/mock/note.md")

    /// 旧値があれば消える。1 つでも取りこぼすと、次に同名のキーを再利用したとき誤って読まれる。
    @Test("旧値のある 5 キーがすべて defaults から消える")
    func removesAllRetiredKeys() {
        let defaults = makeIsolatedDefaults(prefix: "RetiredDisplayStateKeys.present")
        defaults.set([markdown.normalizedPathKey: 120.0], forKey: "ViewerScrollPositions.rendered")
        defaults.set([markdown.normalizedPathKey: 340.0], forKey: "ViewerScrollPositions.source")
        defaults.set([markdown.normalizedPathKey: "source"], forKey: "ViewerDisplayModes")
        defaults.set([markdown.normalizedPathKey: true], forKey: "ViewerSourceModes")
        defaults.set(true, forKey: "SourceDiffEnabled")

        AppStores.removeRetiredDisplayStateKeys(from: defaults)

        for key in AppStores.retiredDisplayStateKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) が残っている")
        }
    }

    /// 旧値が無ければ何も起きない（他のキーを巻き添えにしない）。
    @Test("旧値が無ければ他のキーに触らない")
    func leavesOtherKeysAlone() {
        let defaults = makeIsolatedDefaults(prefix: "RetiredDisplayStateKeys.absent")
        defaults.set([markdown.normalizedPathKey: 1.25], forKey: "ViewerZoomLevels")

        AppStores.removeRetiredDisplayStateKeys(from: defaults)

        #expect(defaults.dictionary(forKey: "ViewerZoomLevels") != nil)
        for key in AppStores.retiredDisplayStateKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    /// 掃除の一覧そのものが縮んでいないこと。キーを 1 つ落とすと上のテストは通ってしまう。
    @Test("掃除する旧キーの一覧が変わっていない")
    func listsExactlyTheRetiredKeys() {
        #expect(AppStores.retiredDisplayStateKeys == [
            "ViewerScrollPositions.rendered",
            "ViewerScrollPositions.source",
            "ViewerDisplayModes",
            "ViewerSourceModes",
            "SourceDiffEnabled",
        ])
    }
}

/// スクロール位置と表示モードが **UserDefaults へ書かれない** ことを、窓を通した
/// 実操作で押さえる（TASK-565）。永続化が復活したらここが落ちる。
///
/// `makeIsolatedDefaults` はメモリ上の実装で、`dictionaryRepresentation()` は
/// 「このテストが書いたもの」だけを返す。したがってキー集合の増分をそのまま比較できる。
@Suite
@MainActor
struct VolatileDisplayStateTests {
    private let file = URL(fileURLWithPath: "/mock/note.md")
    private let other = URL(fileURLWithPath: "/mock/other.md")

    @Test("スクロール位置と表示モードの操作は UserDefaults のキーを増やさない")
    func doesNotWriteVolatileStateToDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "VolatileDisplayState")
        let controller = ViewerWindowControllerFixture(
            file: file, extraFiles: [other], contents: "# hi", defaults: defaults
        ).controller
        defer { controller.close() }
        let before = Set(defaults.dictionaryRepresentation().keys)

        controller.documentPresenter.recordScrollPosition(120, for: file, mode: .rendered)
        controller.setDisplayMode(.source)
        controller.switchFile(to: other)
        controller.switchFile(to: file)

        #expect(Set(defaults.dictionaryRepresentation().keys) == before)
        // 記憶そのものは効いている（何も起きていないから増えなかった、ではない）。
        #expect(controller.isSourceMode)
    }
}
