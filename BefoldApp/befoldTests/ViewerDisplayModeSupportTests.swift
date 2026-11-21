@testable import befold
import Foundation
import Testing

/// 表示モードの降格規則（成立しないモードをその種別で成立するモードへ落とす）を検証する。
/// 規則の置き場は `ViewerDisplayMode.supported(for:)` の 1 箇所だけ。
struct ViewerDisplayModeSupportTests {
    private let markdown = URL(fileURLWithPath: "/mock/note.md")
    private let csv = URL(fileURLWithPath: "/mock/table.csv")
    private let image = URL(fileURLWithPath: "/mock/photo.png")
    private let code = URL(fileURLWithPath: "/mock/main.swift")

    @Test("レンダリング表示はどの種別でもそのまま")
    func keepsRendered() {
        #expect(ViewerDisplayMode.rendered.supported(for: markdown) == .rendered)
        #expect(ViewerDisplayMode.rendered.supported(for: image) == .rendered)
    }

    /// ソース表示を持たない種別(画像・PDF)はレンダリング表示しかできない。
    @Test("ソース表示非対応の種別はレンダリング表示へ降格する")
    func demotesToRenderedForBinaryTypes() {
        #expect(ViewerDisplayMode.source.supported(for: image) == .rendered)
        #expect(ViewerDisplayMode.diff.supported(for: image) == .rendered)
    }

    /// CSV/TSV はソース差分を持たずレンダリング差分だけを持つ(TASK-483)。
    /// 「差分を見たい」という選択はレンダリング差分として残す。
    @Test("CSV の差分はレンダリング差分へ読み替える")
    func csvDiffBecomesRenderedDiff() {
        #expect(ViewerDisplayMode.diff.supported(for: csv) == .renderedDiff)
        #expect(ViewerDisplayMode.renderedDiff.supported(for: csv) == .renderedDiff)
    }

    /// レンダリング差分を持たない種別では、ソース差分(描けなければレンダリング表示)へ落とす。
    @Test("レンダリング差分非対応の種別はソース差分へ降格する")
    func demotesRenderedDiff() {
        #expect(ViewerDisplayMode.renderedDiff.supported(for: code) == .diff)
        #expect(ViewerDisplayMode.renderedDiff.supported(for: image) == .rendered)
        #expect(ViewerDisplayMode.renderedDiff.supported(for: URL(fileURLWithPath: "/mock/page.html")) == .diff)
    }

    /// isSourceMode / showsDiff はモード値だけで決まる(種別に依存させない)。
    @Test("レンダリング差分はソース表示ではなく差分を出す")
    func renderedDiffFlags() {
        #expect(!ViewerDisplayMode.renderedDiff.isSourceMode)
        #expect(ViewerDisplayMode.renderedDiff.showsDiff)
        #expect(ViewerDisplayMode.diff.isSourceMode)
        #expect(ViewerDisplayMode(menuItemTag: 4) == .renderedDiff)
    }

    /// 差分は、ビルド構成によらずそのまま差分として読む(TASK-187)。
    /// 降格の条件は種別(`supportsDiffDisplay`)だけであり、差分を描ける種別なら降格しない。
    @Test("差分を描ける種別では差分がそのまま通る")
    func keepsDiffForSupportedTypes() {
        #expect(ViewerDisplayMode.diff.supported(for: markdown) == .diff)
    }

    /// コード種別は `supportsSourceMode` が false でも差分は重ねられる。
    /// `.diff` の可否を `.source` の条件に相乗りさせると、ここが `.rendered` へ落ちる。
    @Test("コード種別はソース表示へは降格するが差分はそのまま通る")
    func keepsDiffForCodeTypes() {
        #expect(ViewerDisplayMode.source.supported(for: code) == .rendered)
        #expect(ViewerDisplayMode.diff.supported(for: code) == .diff)
    }
}
