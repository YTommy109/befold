@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 新しいウィンドウの出発点になる寸法（窓の種別ごとに 1 個 / TASK-583・TASK-593.5）。
///
/// **ファイル単位の API を持たないことが、この型の設計そのもの。** かつては
/// 正規化パス → 記述子の辞書を持ち「そのファイルの値 → 直近アクティブ窓の値 → この値」の
/// 順で解決していたが、開いた時点で解決結果を各ファイルへ書き戻していたため、一度開いた
/// ファイルは古い寸法に固定され、あとから調整した値が永久に届かなかった。
@MainActor
@Suite
struct WindowFrameStoreTests {
    private func makeStore(_ prefix: String = "WindowFrameStoreTests") -> (WindowFrameStore, UserDefaults) {
        let defaults = makeIsolatedDefaults(prefix: prefix)
        return (WindowFrameStore(defaults: defaults), defaults)
    }

    @Test("調整していなければ nil（呼び出し側が既定サイズへ縮退する）")
    func returnsNilBeforeAnyAdjustment() {
        let (store, _) = makeStore()

        #expect(store.lastUserAdjustedFrameDescriptor(for: .viewer) == nil)
    }

    @Test("記録した寸法をそのまま返す")
    func returnsTheRecordedDescriptor() {
        let (store, _) = makeStore()

        store.recordUserAdjustedFrame("200 200 900 700 0 0 1920 1080", for: .viewer)

        #expect(store.lastUserAdjustedFrameDescriptor(for: .viewer) == "200 200 900 700 0 0 1920 1080")
    }

    @Test("あとから調整した寸法で上書きされる")
    func laterAdjustmentWins() {
        let (store, _) = makeStore()

        store.recordUserAdjustedFrame("200 200 900 700 0 0 1920 1080", for: .viewer)
        store.recordUserAdjustedFrame("10 10 1400 1000 0 0 1920 1080", for: .viewer)

        #expect(store.lastUserAdjustedFrameDescriptor(for: .viewer) == "10 10 1400 1000 0 0 1920 1080")
    }

    @Test("同じ defaults を見る別インスタンスからも読める（永続化されている）")
    func persistsAcrossInstances() {
        let (store, defaults) = makeStore()
        store.recordUserAdjustedFrame("0 0 1280 800 0 0 1920 1080", for: .viewer)

        let reopened = WindowFrameStore(defaults: defaults)

        #expect(reopened.lastUserAdjustedFrameDescriptor(for: .viewer) == "0 0 1280 800 0 0 1920 1080")
    }

    /// 旧実装が使っていたファイル単位の辞書は読まない。移行もしないと決めたので
    /// （`AppStores.retiredDisplayStateKeys` が消す）、値が残っていても影響しない。
    @Test("旧キー WindowFrames が残っていても読まない")
    func ignoresTheRetiredPerFileDictionary() {
        let (store, defaults) = makeStore()
        defaults.set(["/tmp/a.md": "9 9 400 300 0 0 1920 1080"], forKey: "WindowFrames")

        #expect(store.lastUserAdjustedFrameDescriptor(for: .viewer) == nil)
    }

    /// 種別で壺が分かれていることの担保(TASK-593.5)。分かれていないと、プレゼン用に
    /// 広げた寸法が次に開く通常窓へそのまま漏れる。
    @Test("スライド窓の調整は通常窓の寸法を書き換えない")
    func slideAdjustmentDoesNotLeakIntoViewerWindows() {
        let (store, _) = makeStore()
        store.recordUserAdjustedFrame("0 0 1000 800 0 0 1920 1080", for: .viewer)

        store.recordUserAdjustedFrame("0 0 1600 900 0 0 1920 1080", for: .slide)

        #expect(store.lastUserAdjustedFrameDescriptor(for: .viewer) == "0 0 1000 800 0 0 1920 1080")
        #expect(store.lastUserAdjustedFrameDescriptor(for: .slide) == "0 0 1600 900 0 0 1920 1080")
    }

    @Test("通常窓の調整はスライド窓の寸法を書き換えない")
    func viewerAdjustmentDoesNotLeakIntoSlideWindows() {
        let (store, _) = makeStore()
        store.recordUserAdjustedFrame("0 0 1600 900 0 0 1920 1080", for: .slide)

        store.recordUserAdjustedFrame("0 0 1000 800 0 0 1920 1080", for: .viewer)

        #expect(store.lastUserAdjustedFrameDescriptor(for: .slide) == "0 0 1600 900 0 0 1920 1080")
    }

    /// 借りると、まさに避けたい「文書用の寸法でプレゼンが始まる」が初回に起きる。
    @Test("スライド窓が未調整でも通常窓の値へフォールバックしない")
    func slideDoesNotBorrowTheViewerDescriptor() {
        let (store, _) = makeStore()

        store.recordUserAdjustedFrame("0 0 1000 800 0 0 1920 1080", for: .viewer)

        #expect(store.lastUserAdjustedFrameDescriptor(for: .slide) == nil)
    }

    /// 既存利用者が今まで調整してきた寸法を失わないことの担保。通常窓のキーは
    /// 旧実装と同じ `WindowFrameLastUserAdjusted` のまま。
    @Test("通常窓は既存の保存キーをそのまま読む")
    func viewerKeepsReadingTheExistingKey() {
        let (store, defaults) = makeStore()
        defaults.set("7 7 1234 567 0 0 1920 1080", forKey: "WindowFrameLastUserAdjusted")

        #expect(store.lastUserAdjustedFrameDescriptor(for: .viewer) == "7 7 1234 567 0 0 1920 1080")
    }
}
