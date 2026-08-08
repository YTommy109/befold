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
        let store = DisplayModeStore(
            defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.default"),
            isSourceDiffEnabled: true
        )

        #expect(store.displayMode(for: markdown) == .rendered)
    }

    @Test("3 値が往復する", arguments: [ViewerDisplayMode.rendered, .source, .diff])
    func roundTripsAllModes(mode: ViewerDisplayMode) {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.roundTrip")
        DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true).setDisplayMode(mode, for: markdown)

        // 別インスタンスから読み直して、永続化を経ていることまで見る。
        #expect(DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true).displayMode(for: markdown) == mode)
    }

    /// ソース表示を持たない種別(画像・PDF)はレンダリング表示しかできない。
    @Test("ソース表示非対応の種別はレンダリング表示へ降格する")
    func demotesToRenderedForBinaryTypes() {
        let store = DisplayModeStore(
            defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.binary"),
            isSourceDiffEnabled: true
        )
        store.setDisplayMode(.source, for: image)

        #expect(store.restoredDisplayMode(for: image) == .rendered)
        // 保存値そのものは書き換えない。
        #expect(store.displayMode(for: image) == .source)
    }

    /// CSV/TSV は viewer 側が差分を描かないため、差分はソース表示へ落とす。
    @Test("差分非対応の種別はソース表示へ降格する")
    func demotesToSourceForNonDiffTypes() {
        let store = DisplayModeStore(
            defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.csv"),
            isSourceDiffEnabled: true
        )
        store.setDisplayMode(.diff, for: csv)

        #expect(store.restoredDisplayMode(for: csv) == .source)
        #expect(store.displayMode(for: csv) == .diff)
    }

    /// フィーチャーゲートが無効なビルドでは差分を選ぶ手段が露出しないため、
    /// 保存値が差分でもソース表示として読む(保存値は残すので dev へ戻れば復帰する)。
    /// ゲート値は注入するので、dev テストビルドでも OFF 側の分岐を通る。
    @Test("機能ゲートが無効なら差分はソース表示として読む", arguments: [true, false])
    func demotesDiffWhenFeatureUnavailable(isSourceDiffEnabled: Bool) {
        let store = DisplayModeStore(
            defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.gate.\(isSourceDiffEnabled)"),
            isSourceDiffEnabled: isSourceDiffEnabled
        )
        store.setDisplayMode(.diff, for: markdown)

        #expect(store.restoredDisplayMode(for: markdown) == (isSourceDiffEnabled ? .diff : .source))
        // 降格しても保存値は書き換えない(dev ビルドへ戻れば差分のまま復帰する)。
        #expect(store.displayMode(for: markdown) == .diff)
        // 保存値以外の経路(リネーム時のライブなモード引き継ぎ)も同じ規則で降格する。
        #expect(store.supportedDisplayMode(.diff, for: markdown) == (isSourceDiffEnabled ? .diff : .source))
    }

    /// 旧キー(ソース表示 Bool)の記憶を失わせない。true はソース表示、false はレンダリング表示。
    @Test("旧キーの保存値が新キーへ移行される")
    func migratesLegacySourceModes() {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.legacy")
        defaults.set(
            [markdown.normalizedPathKey: true, csv.normalizedPathKey: false], forKey: "ViewerSourceModes"
        )

        let store = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)

        #expect(store.displayMode(for: markdown) == .source)
        #expect(store.displayMode(for: csv) == .rendered)
    }

    /// 旧状態の「差分 ON」はアプリ全体の別キーに載っていた。ソース表示だったファイルは
    /// `.source` ではなく `.diff` として引き継がないと、更新後に差分が消えて見える。
    @Test("旧アプリ全体の差分 ON はソース表示のファイルを差分として引き継ぐ", arguments: [true, false])
    func migratesLegacyDiffEnabled(wasDiffEnabled: Bool) {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.legacyDiff.\(wasDiffEnabled)")
        defaults.set(
            [markdown.normalizedPathKey: true, csv.normalizedPathKey: false], forKey: "ViewerSourceModes"
        )
        defaults.set(wasDiffEnabled, forKey: "SourceDiffEnabled")

        let store = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)

        #expect(store.displayMode(for: markdown) == (wasDiffEnabled ? .diff : .source))
        // 旧状態でレンダリング表示だったファイルは差分 ON でもレンダリング表示のまま。
        #expect(store.displayMode(for: csv) == .rendered)
    }

    /// 読み手の居なくなった旧キーを残さない(移行が走らない場合も含む)。
    @Test("移行後に旧の差分 ON キーが defaults から消える", arguments: [true, false])
    func removesLegacyDiffEnabledKey(hasNewKey: Bool) {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.legacyDiffCleanup.\(hasNewKey)")
        if hasNewKey {
            DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true).setDisplayMode(.rendered, for: markdown)
        }
        defaults.set(true, forKey: "SourceDiffEnabled")

        _ = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)

        #expect(defaults.object(forKey: "SourceDiffEnabled") == nil)
    }

    /// 新キーが既にあるなら旧キーは見ない(移行は 1 度きり)。
    @Test("新キーがあれば旧キーで上書きしない")
    func doesNotOverwriteExistingModes() {
        let defaults = makeIsolatedDefaults(prefix: "DisplayModeStore.noOverwrite")
        DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true).setDisplayMode(.rendered, for: markdown)
        defaults.set([markdown.normalizedPathKey: true], forKey: "ViewerSourceModes")

        #expect(DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true).displayMode(for: markdown) == .rendered)
    }

    @Test("rename で保存値が新パスへ引き継がれる")
    func migratesOnRename() {
        let store = DisplayModeStore(
            defaults: makeIsolatedDefaults(prefix: "DisplayModeStore.rename"),
            isSourceDiffEnabled: true
        )
        let renamed = URL(fileURLWithPath: "/mock/renamed.md")
        store.setDisplayMode(.source, for: markdown)

        store.migrateDisplayMode(from: markdown, to: renamed)

        #expect(store.displayMode(for: renamed) == .source)
        #expect(store.displayMode(for: markdown) == .rendered)
    }
}
