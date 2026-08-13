@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ヘッダーのパスポップアップに出す祖先の並びと、ホームより上へ出さない上限の検証。
///
/// 実ディレクトリを作って測るのは、上限判定 `DirectoryLister.isWithinHome` が
/// `normalizedPathKey`(resolvingSymlinksInPath)で比較するため。合成したパスでは
/// `/var` → `/private/var` の解決が起きず、規則を確かめたことにならない。
struct SidebarPathMenuTests {
    @Test("深い階層では近い親から順にホームまで並ぶ")
    func ancestorsAreOrderedFromNearestParentUpToHome() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let deep = home.url.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

        let ancestors = SidebarPathMenu.ancestors(of: deep, home: home.url)

        #expect(ancestors.map(\.lastPathComponent) == ["b", "a", home.url.lastPathComponent])
        #expect(ancestors.last?.normalizedPathKey == home.url.normalizedPathKey)
    }

    @Test("ホーム直下ではホーム 1 つだけが並び、それより上は現れない")
    func ancestorsAtHomeChildContainsOnlyHome() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let child = home.url.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let ancestors = SidebarPathMenu.ancestors(of: child, home: home.url)

        #expect(ancestors.count == 1)
        #expect(ancestors.first?.normalizedPathKey == home.url.normalizedPathKey)
    }

    @Test("ホーム自身では祖先が無い")
    func ancestorsAtHomeItselfIsEmpty() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }

        #expect(SidebarPathMenu.ancestors(of: home.url, home: home.url).isEmpty)
    }

    @Test("ホーム外では祖先が無い")
    func ancestorsOutsideHomeIsEmpty() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let outside = try TempDir()
        defer { withExtendedLifetime(outside) {} }
        let child = outside.url.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        #expect(SidebarPathMenu.ancestors(of: child, home: home.url).isEmpty)
    }

    /// `parent` を `ancestors.first` 以外の判定で書き直すと落ちる。⌘↑ とメニューが
    /// 別々の上限判定を持つ形へ戻らないための担保(TASK-475)。
    @Test("parent は ancestors の先頭と一致する")
    func parentMatchesFirstAncestorInEveryCase() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let outside = try TempDir()
        defer { withExtendedLifetime(outside) {} }
        let deep = home.url.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

        for directory in [deep, home.url.appendingPathComponent("a"), home.url, outside.url] {
            let expected = SidebarPathMenu.ancestors(of: directory, home: home.url).first
            #expect(
                SidebarPathMenu.parent(of: directory, home: home.url)?.normalizedPathKey
                    == expected?.normalizedPathKey
            )
        }
    }

    @Test("ホーム自身・ホーム外では 1 つ上へ移動できない")
    func parentIsNilAtHomeAndOutsideHome() throws {
        let home = try TempDir()
        defer { withExtendedLifetime(home) {} }
        let outside = try TempDir()
        defer { withExtendedLifetime(outside) {} }

        #expect(SidebarPathMenu.parent(of: home.url, home: home.url) == nil)
        #expect(SidebarPathMenu.parent(of: outside.url, home: home.url) == nil)
    }
}
