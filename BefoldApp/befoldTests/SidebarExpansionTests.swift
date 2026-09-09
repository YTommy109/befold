@testable import befold
import Foundation
import Testing

/// 展開ごとの世代ガードと、展開状態・子リストの保持規則(TASK-361.3)。
/// 実ファイルシステムも SidebarNavigator も通さず、SidebarExpansion 単体で検証する。
@Suite
@MainActor
struct SidebarExpansionTests {
    private let root = URL(fileURLWithPath: "/tmp/SidebarExpansionTests")

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

    // MARK: - 空 / 未到着 / 展開済み の区別（AC #4）

    /// 「空フォルダ」と「まだ届いていない」を配列の空さで判定してはならない
    /// (gitStatus の「空 != nil」と同型 / TASK-285)。
    @Test("空のフォルダは .loaded([]) であり、未到着(.loading)と区別できる")
    func distinguishesEmptyFolderFromPendingChildren() {
        let expansion = SidebarExpansion()
        let target = key("a")

        guard let token = expansion.beginExpanding(target, at: url(forKey: target)) else {
            Issue.record("展開の要求が発行されなかった")
            return
        }
        #expect(expansion.children[target] == .loading)
        // 未到着の間は行を増やさない = 展開集合に載らない。
        #expect(expansion.material.expanded.isEmpty)

        expansion.apply([], for: token)
        #expect(expansion.children[target] == .loaded([]))
        // 答えが出たので展開集合に載る。中身が空でも「展開済み」であることは変わらない。
        #expect(expansion.material.expanded == [target])
        #expect(expansion.material.childrenByPathKey[target] == [])
    }

    // MARK: - 世代ガード（AC #1 / #3 / #6）

    /// サイドバー全体で 1 つの世代にすると、後から始まった B の展開が
    /// 先行する A の結果を捨ててしまう。フォルダごとに分けていればどちらも残る。
    @Test("2 つのフォルダを同時に展開しても、互いの結果を破棄しない")
    func concurrentExpansionsDoNotDiscardEachOther() throws {
        let expansion = SidebarExpansion()
        let dirA = key("a")
        let dirB = key("b")

        let tokenA = expansion.beginExpanding(dirA, at: url(forKey: dirA))
        let tokenB = expansion.beginExpanding(dirB, at: url(forKey: dirB))

        // B を先に着地させてから A を着地させる(A の列挙のほうが遅かった場合)。
        try expansion.apply([entry("b/1.md")], for: #require(tokenB))
        try expansion.apply([entry("a/1.md")], for: #require(tokenA))

        #expect(expansion.material.expanded == [dirA, dirB])
        #expect(expansion.material.childrenByPathKey[dirA]?.count == 1)
        #expect(expansion.material.childrenByPathKey[dirB]?.count == 1)
    }

    /// 開始時の無効化。畳んでから再度展開すると世代が 2 回進むため、
    /// 最初の要求の結果が遅れて届いても捨てられる。
    @Test("畳んでから再展開すると、古い要求の結果は反映されない")
    func staleResultAfterCollapseAndReexpandIsDiscarded() throws {
        let expansion = SidebarExpansion()
        let target = key("a")

        let stale = expansion.beginExpanding(target, at: url(forKey: target))
        expansion.collapse(target)
        let fresh = expansion.beginExpanding(target, at: url(forKey: target))

        try expansion.apply([entry("a/stale.md")], for: #require(stale))
        #expect(expansion.children[target] == .loading)

        try expansion.apply([entry("a/fresh.md")], for: #require(fresh))
        #expect(
            expansion.material.childrenByPathKey[target]?.map(\.url.lastPathComponent)
                == ["fresh.md"]
        )
    }

    /// 着地時の一致確認。ルート切り替え(invalidateAll)後に届いた結果は、
    /// フォルダ世代だけを見ていると通ってしまう。
    @Test("ルート切り替え後に届いた結果は反映されない")
    func resultArrivingAfterRootSwitchIsDiscarded() throws {
        let expansion = SidebarExpansion()
        let target = key("a")

        let token = expansion.beginExpanding(target, at: url(forKey: target))
        expansion.invalidateAll()
        try expansion.apply([entry("a/1.md")], for: #require(token))

        #expect(expansion.expandedKeys.isEmpty)
        #expect(expansion.children.isEmpty)
        #expect(expansion.material.expanded.isEmpty)
    }

    // MARK: - 畳みの波及

    /// 配下を残す設計にすると、畳んでいる間に走行中だった配下の列挙が着地して
    /// 子リストを書き、再展開したときに古い内容がそのまま復活する。
    @Test("フォルダを畳むと、その配下の展開も一緒に捨てられる")
    func collapseCascadesToDescendants() throws {
        let expansion = SidebarExpansion()
        let outer = key("a")
        let inner = key("a/b")

        let outerToken = expansion.beginExpanding(outer, at: url(forKey: outer))
        let innerToken = expansion.beginExpanding(inner, at: url(forKey: inner))
        try expansion.apply([entry("a/b")], for: #require(outerToken))
        try expansion.apply([entry("a/b/1.md")], for: #require(innerToken))
        #expect(expansion.expandedKeys == [outer, inner])

        expansion.collapse(outer)

        #expect(expansion.expandedKeys.isEmpty)
        #expect(expansion.children[inner] == nil)
    }

    /// 兄弟パスを配下と取り違えない。区切り文字を含めずに前方一致すると
    /// `/tmp/.../ab` が `/tmp/.../a` の配下として巻き添えで畳まれる。
    @Test("畳みの波及は兄弟パスに及ばない")
    func collapseDoesNotCascadeToSiblingPaths() throws {
        let expansion = SidebarExpansion()
        let target = key("a")
        let sibling = key("ab")

        _ = expansion.beginExpanding(target, at: url(forKey: target))
        let siblingToken = expansion.beginExpanding(sibling, at: url(forKey: sibling))
        try expansion.apply([entry("ab/1.md")], for: #require(siblingToken))

        expansion.collapse(target)

        #expect(expansion.expandedKeys == [sibling])
    }

    // MARK: - コスト（AC #5）

    /// 「展開 1 回につき列挙 1 回」。既に展開済みのフォルダを再度展開しようとしても
    /// トークンを発行しない = 呼び出し側が列挙を走らせない。
    @Test("展開済みのフォルダを再度展開しても、列挙は要求されない")
    func expandingAlreadyExpandedFolderDoesNotRequestListing() {
        let expansion = SidebarExpansion()
        let target = key("a")

        #expect(expansion.beginExpanding(target, at: url(forKey: target)) != nil)
        #expect(expansion.beginExpanding(target, at: url(forKey: target)) == nil)
    }

    /// 並び順・隠しファイル表示が変わったら取り直す。取り直さないと、展開中の
    /// サブツリーだけが古い規則で並び続ける。
    ///
    /// このとき手元の子リストを `.loading` へ戻してはならない。戻すと新しい子が届くまで
    /// 展開が畳まれた形になり、その間に走る選択維持の判定で、展開したサブフォルダ内の
    /// ファイルを選んでいた利用者の選択が失われる。
    @Test("取り直しの間も、手元の子リストはそのまま出し続ける")
    func invalidateChildrenKeepsLoadedChildrenWhileReloading() throws {
        let expansion = SidebarExpansion()
        let target = key("a")
        let token = expansion.beginExpanding(target, at: url(forKey: target))
        try expansion.apply([entry("a/1.md")], for: #require(token))

        let reloads = expansion.invalidateChildren()

        #expect(reloads.map(\.key) == [target])
        #expect(expansion.expandedKeys == [target])
        #expect(expansion.children[target] == .loaded([entry("a/1.md")]))
        #expect(expansion.material.expanded == [target])
    }

    /// 取り直しを要求した時点で世代が進むため、その前に走っていた列挙の結果は捨てられる。
    @Test("取り直しを挟むと、直前まで走っていた列挙の結果は反映されない")
    func invalidateChildrenDiscardsInFlightResult() throws {
        let expansion = SidebarExpansion()
        let target = key("a")
        let stale = expansion.beginExpanding(target, at: url(forKey: target))

        _ = expansion.invalidateChildren()
        try expansion.apply([entry("a/stale.md")], for: #require(stale))

        #expect(expansion.children[target] == .loading)
    }

    @Test("展開が無ければ取り直しは要求されない")
    func invalidateChildrenIsNoOpWithoutExpansion() {
        let expansion = SidebarExpansion()

        #expect(expansion.invalidateChildren().isEmpty)
    }

    // MARK: - 券が運ぶフォルダ URL（TASK-442.3 / AC #3）

    /// 取り直しの券は、展開を始めたときに渡された URL をそのまま運ぶ。
    /// これが無いと、受け取り側が pathKey から URL を引き当て直すことになり、
    /// 引き当て先の一覧が組み直しの途中(その key の行がまだ無い)だと取り直しが
    /// 黙って落ちる。**この期待が壊れたら引き当てが復活したということ。**
    @Test("取り直しの券は、展開開始時に渡されたフォルダ URL を運ぶ")
    func invalidateChildrenCarriesOriginalFolderURL() throws {
        let expansion = SidebarExpansion()
        let target = key("a")
        let folder = url(forKey: target)
        let token = try #require(expansion.beginExpanding(target, at: folder))
        #expect(token.url == folder)

        let reload = try #require(expansion.invalidateChildren().first)

        #expect(reload.key == target)
        #expect(reload.url == folder)
    }

    /// 券は展開開始時の URL を運ぶので、その後フォルダがリネーム・削除されていれば
    /// 列挙は失敗し `.failed` が着地する(引き当て方式のときは「引けなかったので
    /// 何もしない」だった)。**表示は変わらない**——その pathKey はルート再列挙後に
    /// どの行とも一致せず、`material.failed` に入っても行を持たないため。
    /// 引き当て方式へ戻すかどうかの判断材料としてここに固定する。
    @Test("消えたフォルダの取り直しは .failed が着地するが、行は生まれない")
    func staleFolderReloadLandsFailedWithoutRows() throws {
        let expansion = SidebarExpansion()
        let target = key("gone")
        let token = try #require(expansion.beginExpanding(target, at: url(forKey: target)))
        expansion.apply([entry("gone/1.md")], for: token)

        let reload = try #require(expansion.invalidateChildren().first)
        expansion.apply(nil, for: reload)

        #expect(expansion.children[target] == .failed)
        #expect(expansion.material.failed == [target])
        #expect(expansion.material.childrenByPathKey[target] == nil)
    }
}
