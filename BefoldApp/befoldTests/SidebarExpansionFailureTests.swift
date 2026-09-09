@testable import befold
import Foundation
import Testing

/// 列挙に失敗したフォルダの扱い(TASK-404)。境界は**フォルダの状態が 3 値である**こと
/// ——`.loaded` / `.loading` / `.failed` を配列の空さで判定してはならない、という 1 つの
/// 規則に属するテストだけをここへ置く。どの結果を採るかの世代ガードは
/// `SidebarExpansionTests`、レイアウト切替のスナップショット root は
/// `SidebarExpansionSnapshotRootTests` にある。
///
/// ヘルパー 3 本は `SidebarExpansionTests` と同形だが、`private`(ファイルスコープ)なので
/// ここに置く。共有すると root の名前まで共有することになり、どちらのスイートが作った
/// 一時パスかが読めなくなる。
@Suite
@MainActor
struct SidebarExpansionFailureTests {
    private let root = URL(fileURLWithPath: "/tmp/SidebarExpansionFailureTests")

    private func key(_ path: String) -> String {
        root.appendingPathComponent(path).normalizedPathKey
    }

    private func entry(_ path: String) -> FileListEntry {
        FileListEntry(url: root.appendingPathComponent(path), kind: .file)
    }

    /// pathKey に対応するフォルダ URL。券に載せる値の検証だけに使うので、
    /// 実在する必要はない(このスイートは実ファイルシステムを触らない)。
    private func url(forKey key: String) -> URL {
        URL(fileURLWithPath: key)
    }

    /// 列挙失敗を `.loaded([])` へ畳むと、権限の無いフォルダが「空のフォルダ」として
    /// 確定表示される。`.loading` へ寄せると永久にスピナーが回る。どちらとも別にする。
    @Test("列挙失敗は .failed であり、空フォルダとも未到着とも区別できる")
    func distinguishesFailureFromEmptyAndPending() throws {
        let expansion = SidebarExpansion()
        let target = key("a")

        let token = try #require(expansion.beginExpanding(target, at: url(forKey: target)))
        expansion.apply(nil, for: token)

        #expect(expansion.children[target] == .failed)
        #expect(expansion.children[target] != .loaded([]))
        #expect(expansion.children[target] != .loading)
    }

    /// `material` の 3 つの集合は互いに素。ここが崩れると、失敗が「読み込み中」として
    /// 永久にスピナーになる（`guard case .loaded ... else { loading }` の形が実際にそう落ちる）。
    @Test("material の expanded / loading / failed は互いに素")
    func materialSetsAreDisjoint() throws {
        let expansion = SidebarExpansion()
        let loaded = key("loaded")
        let pending = key("pending")
        let failed = key("failed")

        let loadedToken = try #require(expansion.beginExpanding(loaded, at: url(forKey: loaded)))
        expansion.apply([entry("loaded/1.md")], for: loadedToken)
        _ = expansion.beginExpanding(pending, at: url(forKey: pending))
        let failedToken = try #require(expansion.beginExpanding(failed, at: url(forKey: failed)))
        expansion.apply(nil, for: failedToken)

        let material = expansion.material
        #expect(material.expanded == [loaded])
        #expect(material.loading == [pending])
        #expect(material.failed == [failed])
        #expect(material.expanded.isDisjoint(with: material.loading))
        #expect(material.expanded.isDisjoint(with: material.failed))
        #expect(material.loading.isDisjoint(with: material.failed))
        // 失敗したフォルダには並べる子が無いので、行の材料も持たない。
        #expect(material.childrenByPathKey[failed] == nil)
    }

    /// 失敗したまま `expandedKeys` に残ると、以後の展開操作が「展開済み」として弾かれ、
    /// いったん畳むまで再試行できない。失敗時だけ再展開を通す。
    @Test("列挙に失敗したフォルダは、畳まずに再展開して取り直せる")
    func failedFolderCanBeRetriedWithoutCollapsing() throws {
        let expansion = SidebarExpansion()
        let target = key("a")

        let first = try #require(expansion.beginExpanding(target, at: url(forKey: target)))
        expansion.apply(nil, for: first)

        let retry = try #require(expansion.beginExpanding(target, at: url(forKey: target)))
        #expect(expansion.children[target] == .loading)

        expansion.apply([entry("a/1.md")], for: retry)
        #expect(expansion.children[target] == .loaded([entry("a/1.md")]))
        #expect(expansion.material.expanded == [target])
    }

    /// 成功したフォルダの「展開 1 回につき列挙 1 回」の上限は変えない。
    @Test("読み込めたフォルダの再展開は、列挙を要求しない")
    func loadedFolderIsNotReExpanded() throws {
        let expansion = SidebarExpansion()
        let target = key("a")

        let token = try #require(expansion.beginExpanding(target, at: url(forKey: target)))
        expansion.apply([entry("a/1.md")], for: token)

        #expect(expansion.beginExpanding(target, at: url(forKey: target)) == nil)
    }

    /// 取り直し(並び順の変更・隠しファイルのトグル等)は失敗したフォルダも対象にする。
    /// 権限が変わった後に自動で回復する経路はここ。
    @Test("取り直しは失敗したフォルダも対象にし、成功すれば .loaded へ戻る")
    func invalidateChildrenRecoversFailedFolder() throws {
        let expansion = SidebarExpansion()
        let target = key("a")

        let failedToken = try #require(expansion.beginExpanding(target, at: url(forKey: target)))
        expansion.apply(nil, for: failedToken)

        let reloads = expansion.invalidateChildren()
        #expect(reloads.map(\.key) == [target])

        try expansion.apply([entry("a/1.md")], for: #require(reloads.first))
        #expect(expansion.children[target] == .loaded([entry("a/1.md")]))
    }

    /// 世代・epoch のガードは失敗の着地にも効く(失敗を別の入口に分けていない担保)。
    @Test("取り直しを挟むと、直前まで走っていた列挙の失敗も反映されない")
    func invalidateChildrenDiscardsInFlightFailure() throws {
        let expansion = SidebarExpansion()
        let target = key("a")
        let stale = expansion.beginExpanding(target, at: url(forKey: target))

        _ = expansion.invalidateChildren()
        try expansion.apply(nil, for: #require(stale))

        #expect(expansion.children[target] == .loading)
    }

    @Test("要求していないフォルダの状態は nil(未到着とも区別される)")
    func unrequestedFolderHasNoState() {
        let expansion = SidebarExpansion()

        #expect(expansion.children[key("never")] == nil)
    }
}
