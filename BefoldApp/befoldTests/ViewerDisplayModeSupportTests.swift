@testable import befold
import Foundation
import Testing

/// 表示モードの降格規則（成立しないモードをその種別で成立するモードへ落とす）を検証する。
/// 規則の置き場は `ViewerDisplayMode.supported(for:)` の 1 箇所だけ。
@MainActor
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

    /// CSV/TSV は viewer 側が差分を描かないため、差分はソース表示へ落とす。
    @Test("差分非対応の種別はソース表示へ降格する")
    func demotesToSourceForNonDiffTypes() {
        #expect(ViewerDisplayMode.diff.supported(for: csv) == .source)
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
