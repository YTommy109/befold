@testable import befold
import Foundation
import Testing

@Suite
struct SessionLayoutTests {
    /// **窓ごとの寸法は絞り込みで落とさない(TASK-583)。** 復元は「存在するパスだけに絞る」
    /// 工程を必ず通るので、ここで frame が落ちると、閉じられたタブが 1 つあるだけで
    /// その窓の寸法が失われる。
    @Test("絞り込んでも窓の寸法は保たれる")
    func filteredKeepsTheWindowFrame() {
        let layout = SessionLayout(groups: [
            SessionLayout.TabGroup(
                paths: ["/a", "/b"], selectedPath: "/b", frame: "0 0 900 700 0 0 1920 1080"
            ),
        ])

        let filtered = layout.filtered(to: ["/a"])

        #expect(filtered.groups.first?.frame == "0 0 900 700 0 0 1920 1080")
    }

    /// この項目を持たない保存済みレイアウト(旧バージョン)をそのまま読めること。
    /// 読めないと、更新した最初の起動で前回のタブ構成ごと失われる。
    @Test("frame の無い保存済みレイアウトも読める")
    func decodesLayoutWithoutFrame() throws {
        let json = Data(#"{"groups":[{"paths":["/a"],"selectedPath":"/a"}]}"#.utf8)

        let layout = try JSONDecoder().decode(SessionLayout.self, from: json)

        #expect(layout.groups == [SessionLayout.TabGroup(paths: ["/a"], selectedPath: "/a")])
        #expect(layout.groups.first?.frame == nil)
    }

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
