@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ファイル単位の表示モード永続化(3 値の往復・成立しないモードの降格・旧キーからの移行)を検証する。
@MainActor
struct DisplayModeStoreTests {
    private let markdown = URL(fileURLWithPath: "/mock/note.md")
    private let csv = URL(fileURLWithPath: "/mock/table.csv")
    private let image = URL(fileURLWithPath: "/mock/photo.png")

    @Test("保存がなければレンダリング表示")
    func defaultsToRendered() {
        let store = DisplayModeStore(defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.default"))

        #expect(store.displayMode(for: markdown) == .rendered)
    }

    @Test("3 値が往復する", arguments: [ViewerDisplayMode.rendered, .source, .diff])
    func roundTripsAllModes(mode: ViewerDisplayMode) {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.roundTrip")
        DisplayModeStore(defaults: defaults).setDisplayMode(mode, for: markdown)

        // 別インスタンスから読み直して、永続化を経ていることまで見る。
        #expect(DisplayModeStore(defaults: defaults).displayMode(for: markdown) == mode)
    }

    /// ソース表示を持たない種別(画像・PDF)はレンダリング表示しかできない。
    @Test("ソース表示非対応の種別はレンダリング表示へ降格する")
    func demotesToRenderedForBinaryTypes() {
        let store = DisplayModeStore(defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.binary"))
        store.setDisplayMode(.source, for: image)

        #expect(store.restoredDisplayMode(for: image) == .rendered)
        // 保存値そのものは書き換えない。
        #expect(store.displayMode(for: image) == .source)
    }

    /// CSV/TSV は viewer 側が差分を描かないため、差分はソース表示へ落とす。
    @Test("差分非対応の種別はソース表示へ降格する")
    func demotesToSourceForNonDiffTypes() {
        let store = DisplayModeStore(defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.csv"))
        store.setDisplayMode(.diff, for: csv)

        #expect(store.restoredDisplayMode(for: csv) == .source)
        #expect(store.displayMode(for: csv) == .diff)
    }

    /// フィーチャーゲートが無効なビルドでは差分を選ぶ手段が露出しないため、
    /// 保存値が差分でもソース表示として読む(保存値は残すので dev へ戻れば復帰する)。
    @Test("機能ゲートが無効なら差分はソース表示として読む")
    func demotesDiffWhenFeatureUnavailable() {
        let store = DisplayModeStore(defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.gate"))
        store.setDisplayMode(.diff, for: markdown)

        let expected: ViewerDisplayMode = FeatureGate.isSourceDiffEnabled ? .diff : .source
        #expect(store.restoredDisplayMode(for: markdown) == expected)
    }

    /// 旧キー(ソース表示 Bool)の記憶を失わせない。true はソース表示、false はレンダリング表示。
    @Test("旧キーの保存値が新キーへ移行される")
    func migratesLegacySourceModes() {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.legacy")
        defaults.set(
            [markdown.normalizedPathKey: true, csv.normalizedPathKey: false], forKey: "ViewerSourceModes"
        )

        let store = DisplayModeStore(defaults: defaults)

        #expect(store.displayMode(for: markdown) == .source)
        #expect(store.displayMode(for: csv) == .rendered)
    }

    /// 新キーが既にあるなら旧キーは見ない(移行は 1 度きり)。
    @Test("新キーがあれば旧キーで上書きしない")
    func doesNotOverwriteExistingModes() {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.noOverwrite")
        DisplayModeStore(defaults: defaults).setDisplayMode(.rendered, for: markdown)
        defaults.set([markdown.normalizedPathKey: true], forKey: "ViewerSourceModes")

        #expect(DisplayModeStore(defaults: defaults).displayMode(for: markdown) == .rendered)
    }

    @Test("rename で保存値が新パスへ引き継がれる")
    func migratesOnRename() {
        let store = DisplayModeStore(defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.rename"))
        let renamed = URL(fileURLWithPath: "/mock/renamed.md")
        store.setDisplayMode(.source, for: markdown)

        store.migrateDisplayMode(from: markdown, to: renamed)

        #expect(store.displayMode(for: renamed) == .source)
        #expect(store.displayMode(for: markdown) == .rendered)
    }
}
