@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 窓の生存期間だけのファイル単位の記憶（スクロール位置・表示モード）を検証する。
@MainActor
struct WindowPresentationMemoryTests {
    private let markdown = URL(fileURLWithPath: "/mock/note.md")
    private let other = URL(fileURLWithPath: "/mock/other.md")
    private let image = URL(fileURLWithPath: "/mock/photo.png")

    @Test("記憶が無ければ先頭(0)とレンダリング表示")
    func defaultsToTopAndRendered() {
        let memory = WindowPresentationMemory()

        #expect(memory.scrollPosition(for: markdown, mode: .rendered) == 0)
        #expect(memory.scrollPosition(for: markdown, mode: .source) == 0)
        #expect(memory.displayMode(for: markdown) == .rendered)
    }

    @Test("スクロール位置が往復する")
    func roundTripsScrollPosition() {
        let memory = WindowPresentationMemory()

        memory.setScrollPosition(120, for: markdown, mode: .rendered)

        #expect(memory.scrollPosition(for: markdown, mode: .rendered) == 120)
    }

    /// レンダリング表示とソース表示は DOM 構造が異なり位置に連続性がない。
    @Test("スクロール位置はモードごとに独立している")
    func keepsScrollPositionPerMode() {
        let memory = WindowPresentationMemory()

        memory.setScrollPosition(120, for: markdown, mode: .rendered)
        memory.setScrollPosition(340, for: markdown, mode: .source)

        #expect(memory.scrollPosition(for: markdown, mode: .rendered) == 120)
        #expect(memory.scrollPosition(for: markdown, mode: .source) == 340)
    }

    @Test("スクロール位置と表示モードはファイルごとに独立している")
    func keepsStatePerFile() {
        let memory = WindowPresentationMemory()

        memory.setScrollPosition(120, for: markdown, mode: .rendered)
        memory.setDisplayMode(.source, for: markdown)

        #expect(memory.scrollPosition(for: other, mode: .rendered) == 0)
        #expect(memory.displayMode(for: other) == .rendered)
    }

    @Test("表示モードが往復する", arguments: [ViewerDisplayMode.rendered, .source, .diff])
    func roundTripsAllModes(mode: ViewerDisplayMode) {
        let memory = WindowPresentationMemory()

        memory.setDisplayMode(mode, for: markdown)

        #expect(memory.displayMode(for: markdown) == mode)
    }

    /// 降格規則は `ViewerDisplayMode.supported(for:)` に閉じており、記憶は書き換えない。
    @Test("復元時は成立しないモードを降格するが、記憶そのものは書き換えない")
    func demotesOnRestoreWithoutRewriting() {
        let memory = WindowPresentationMemory()

        memory.setDisplayMode(.source, for: image)

        #expect(memory.restoredDisplayMode(for: image) == .rendered)
        #expect(memory.displayMode(for: image) == .source)
    }

    @Test("rename で記憶が新パスへ引き継がれる")
    func migratesOnRename() {
        let memory = WindowPresentationMemory()
        let renamed = URL(fileURLWithPath: "/mock/renamed.md")
        memory.setScrollPosition(120, for: markdown, mode: .rendered)
        memory.setScrollPosition(340, for: markdown, mode: .source)
        memory.setDisplayMode(.source, for: markdown)

        memory.migrate(from: markdown, to: renamed)

        #expect(memory.scrollPosition(for: renamed, mode: .rendered) == 120)
        #expect(memory.scrollPosition(for: renamed, mode: .source) == 340)
        #expect(memory.displayMode(for: renamed) == .source)
        // 旧パスの記憶は残さない。
        #expect(memory.scrollPosition(for: markdown, mode: .rendered) == 0)
        #expect(memory.displayMode(for: markdown) == .rendered)
    }

    /// キーの正規化は永続側(`PathKeyedDictionary`)と同じ規約でなければならない。
    /// 永続側の symlink テストは揮発側を守らないので、こちらにも置く。
    @Test("シンボリックリンク経由でも同一ファイルとして扱う")
    func resolvesSymlinkToSamePath() throws {
        let memory = WindowPresentationMemory()
        let tmp = try TempDir(prefix: "WindowPresentationMemoryTests")
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedFile()

        memory.setScrollPosition(120, for: link, mode: .rendered)
        memory.setDisplayMode(.source, for: link)

        #expect(memory.scrollPosition(for: real, mode: .rendered) == 120)
        #expect(memory.displayMode(for: real) == .source)
    }

    /// **揮発であることのトリップワイヤ。** 新しいインスタンスは常に空から始まる。
    /// `UserDefaults` を触る stored property が生えたらここが落ちる。
    @Test("新しいインスタンスは何も覚えていない")
    func startsEmpty() {
        WindowPresentationMemory().setScrollPosition(120, for: markdown, mode: .rendered)
        WindowPresentationMemory().setDisplayMode(.source, for: markdown)

        let fresh = WindowPresentationMemory()
        #expect(fresh.scrollPosition(for: markdown, mode: .rendered) == 0)
        #expect(fresh.displayMode(for: markdown) == .rendered)
    }
}
