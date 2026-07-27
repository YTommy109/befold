@testable import BefoldKit
import Foundation
import Testing

/// Quick Open は索引に取り込まれた候補そのものを一覧したいが、`SuffixPathIndex` は
/// 照合結果しか返さない。読み出し口 `allCandidates` の契約をここで固定する。
/// 照合規則には触れないため、既存の解決挙動は変わらない。
struct SuffixPathIndexCandidatesTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test("取り込んだ候補をすべて読み出せる")
    func exposesAllCandidates() {
        let candidates = [url("/repo/src/a.swift"), url("/repo/docs/b.md")]
        let index = SuffixPathIndex(candidates: candidates)

        #expect(Set(index.allCandidates) == Set(candidates))
    }

    @Test("読み出し順は正規化パス昇順で決定論的になる")
    func ordersByStandardizedPath() {
        let index = SuffixPathIndex(candidates: [
            url("/repo/z.md"), url("/repo/a.md"), url("/repo/m.md"),
        ])

        #expect(index.allCandidates == [url("/repo/a.md"), url("/repo/m.md"), url("/repo/z.md")])
    }

    /// 構成要素を持たない候補は照合対象から落とされる(既存の init の挙動)。
    /// 読み出し口もその落とし方に揃え、照合できない候補を一覧に出さない。
    @Test("構成要素を持たない候補は読み出しにも含まれない")
    func dropsRootCandidate() {
        let index = SuffixPathIndex(candidates: [url("/"), url("/repo/a.md")])

        #expect(index.allCandidates == [url("/repo/a.md")])
    }

    @Test("候補ゼロなら空を返す")
    func emptyIndex() {
        #expect(SuffixPathIndex(candidates: []).allCandidates.isEmpty)
    }
}
