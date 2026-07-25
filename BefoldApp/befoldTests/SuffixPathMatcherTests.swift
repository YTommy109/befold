@testable import BefoldKit
import Foundation
import Testing

struct SuffixPathMatcherTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test("構成要素単位のサフィックス一致で候補を絞る")
    func matchesOnComponentBoundary() {
        let candidates = [
            url("/repo/src/utils.swift"),
            url("/repo/src/myutils.swift"),
        ]
        let base = url("/repo/docs/guide.md")
        // "utils.swift" は myutils.swift の部分文字列だが構成要素境界では一致しない
        let result = SuffixPathMatcher.bestMatch(
            writtenPath: "utils.swift",
            candidates: candidates,
            baseURL: base
        )
        #expect(result == url("/repo/src/utils.swift"))
    }

    @Test("複数候補は開いているファイルに近いものを選ぶ")
    func picksClosestToBase() {
        let candidates = [
            url("/repo/packages/web/src/utils.swift"),
            url("/repo/packages/api/src/utils.swift"),
        ]
        let base = url("/repo/packages/web/docs/guide.md")
        let result = SuffixPathMatcher.bestMatch(
            writtenPath: "utils.swift",
            candidates: candidates,
            baseURL: base
        )
        #expect(result == url("/repo/packages/web/src/utils.swift"))
    }

    @Test("多段のサフィックスはより長く一致する候補に絞られる")
    func matchesMultiComponentSuffix() {
        let candidates = [
            url("/repo/packages/web/src/foo/bar.ts"),
            url("/repo/other/bar.ts"),
        ]
        let base = url("/repo/README.md")
        let result = SuffixPathMatcher.bestMatch(
            writtenPath: "src/foo/bar.ts",
            candidates: candidates,
            baseURL: base
        )
        #expect(result == url("/repo/packages/web/src/foo/bar.ts"))
    }

    @Test("先頭の ./ ../ / は無視して照合する")
    func ignoresLeadingDots() {
        let candidates = [url("/repo/src/a.swift")]
        let base = url("/repo/docs/guide.md")
        let result = SuffixPathMatcher.bestMatch(
            writtenPath: "../src/a.swift",
            candidates: candidates,
            baseURL: base
        )
        #expect(result == url("/repo/src/a.swift"))
    }

    @Test("該当なしは nil")
    func noMatchReturnsNil() {
        let result = SuffixPathMatcher.bestMatch(
            writtenPath: "nope.swift",
            candidates: [url("/repo/a.swift")],
            baseURL: url("/repo/x.md")
        )
        #expect(result == nil)
    }

    @Test("距離同点は up 段数最小→path 昇順で決定論的に確定する")
    func deterministicTieBreak() {
        let candidates = [url("/repo/b/x.swift"), url("/repo/a/x.swift")]
        let base = url("/repo/base/guide.md") // 両候補とも距離2・up1で同点
        let result = SuffixPathMatcher.bestMatch(
            writtenPath: "x.swift",
            candidates: candidates,
            baseURL: base
        )
        #expect(result == url("/repo/a/x.swift"))
    }
}
