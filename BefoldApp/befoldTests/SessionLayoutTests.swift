import Foundation
@testable import mmdview
import Testing

@Suite
struct SessionLayoutTests {
    @Test("存在しないパスを除き、消えた選択タブは先頭で代替する")
    func filteredKeepsOnlyAvailablePaths() {
        let layout = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: ["/a", "/b", "/c"], selectedPath: "/b"),
        ])

        let filtered = layout.filtered(to: ["/a", "/c"])

        #expect(filtered.groups == [SessionLayout.TabGroup(paths: ["/a", "/c"], selectedPath: "/a")])
    }

    @Test("全ファイルが消えたグループは取り除かれる")
    func filteredDropsEmptyGroups() {
        let layout = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: ["/a"], selectedPath: "/a"),
            SessionLayout.TabGroup(paths: ["/gone"], selectedPath: "/gone"),
        ])

        let filtered = layout.filtered(to: ["/a"])

        #expect(filtered.groups == [SessionLayout.TabGroup(paths: ["/a"], selectedPath: "/a")])
    }

    @Test
    func filteredKeepsSelectedPathWhenAvailable() {
        let layout = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: ["/a", "/b"], selectedPath: "/b"),
        ])

        let filtered = layout.filtered(to: ["/a", "/b"])

        #expect(filtered.groups.first?.selectedPath == "/b")
    }

    @Test("選択タブが未設定のグループは先頭タブを選択にする")
    func filteredPromotesNilSelectedPathToFirst() {
        let layout = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: ["/a", "/b"], selectedPath: nil),
        ])

        let filtered = layout.filtered(to: ["/a", "/b"])

        #expect(filtered.groups.first?.selectedPath == "/a")
    }
}
