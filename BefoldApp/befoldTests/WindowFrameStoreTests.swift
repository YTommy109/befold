@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 新しいウィンドウの出発点になる寸法（アプリ全体で 1 個 / TASK-583）。
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

        #expect(store.lastUserAdjustedFrameDescriptor == nil)
    }

    @Test("記録した寸法をそのまま返す")
    func returnsTheRecordedDescriptor() {
        let (store, _) = makeStore()

        store.recordUserAdjustedFrame("200 200 900 700 0 0 1920 1080")

        #expect(store.lastUserAdjustedFrameDescriptor == "200 200 900 700 0 0 1920 1080")
    }

    @Test("あとから調整した寸法で上書きされる")
    func laterAdjustmentWins() {
        let (store, _) = makeStore()

        store.recordUserAdjustedFrame("200 200 900 700 0 0 1920 1080")
        store.recordUserAdjustedFrame("10 10 1400 1000 0 0 1920 1080")

        #expect(store.lastUserAdjustedFrameDescriptor == "10 10 1400 1000 0 0 1920 1080")
    }

    @Test("同じ defaults を見る別インスタンスからも読める（永続化されている）")
    func persistsAcrossInstances() {
        let (store, defaults) = makeStore()
        store.recordUserAdjustedFrame("0 0 1280 800 0 0 1920 1080")

        let reopened = WindowFrameStore(defaults: defaults)

        #expect(reopened.lastUserAdjustedFrameDescriptor == "0 0 1280 800 0 0 1920 1080")
    }

    /// 旧実装が使っていたファイル単位の辞書は読まない。移行もしないと決めたので
    /// （`AppStores.retiredDisplayStateKeys` が消す）、値が残っていても影響しない。
    @Test("旧キー WindowFrames が残っていても読まない")
    func ignoresTheRetiredPerFileDictionary() {
        let (store, defaults) = makeStore()
        defaults.set(["/tmp/a.md": "9 9 400 300 0 0 1920 1080"], forKey: "WindowFrames")

        #expect(store.lastUserAdjustedFrameDescriptor == nil)
    }
}
