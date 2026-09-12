import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// タブ結合は実 NSWindow の tabGroup を使うため、MockedViewerWindowManager 経由で
/// 実ウィンドウを生成して検証する(store と directoryLister はモック済み)。
@Suite
@MainActor
struct ViewerWindowManagerTabTests {
    /// 新しいタブは背面で開き、選択は起点に留まる(Safari の cmd+クリックと同じ。TASK-611)。
    @Test("newTab で開くと起点ウィンドウのタブグループに入るが、選択タブは起点のまま")
    func newTabJoinsSourceTabGroupInBackground() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newTab, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup != nil)
        #expect(secondWindow?.tabGroup === firstWindow?.tabGroup)
        #expect(secondWindow?.tabGroup?.selectedWindow === firstWindow)
    }

    /// 置き場所が openViewer から attachAsTab まで届くこと(TASK-611)。並びは実ウィンドウの
    /// tabGroup.windows で見る。起点を常に 1 枚目にして、`.end` と `.afterSource` で結果が
    /// 分かれることを 1 つのテストで固定する。
    @Test("newTab の置き場所: end は末尾、afterSource は起点の直後")
    func newTabPlacementControlsInsertionPosition() throws {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let third = URL(fileURLWithPath: "/mock/third.md")
        let fixture = MockedViewerWindowManager(
            files: [first, second, third], prefix: "ViewerWindowManagerTabTests"
        )
        defer { fixture.closeAll() }
        let firstWindow = try #require(fixture.manager.openViewer(for: first)?.window)

        let secondWindow = try #require(
            fixture.manager.openViewer(
                for: second, disposition: .newTab, relativeTo: firstWindow, tabPlacement: .end
            )?.window
        )
        let thirdWindow = try #require(
            fixture.manager.openViewer(
                for: third, disposition: .newTab, relativeTo: firstWindow, tabPlacement: .afterSource
            )?.window
        )

        let order = firstWindow.tabGroup?.windows.map(ObjectIdentifier.init)
        #expect(order == [firstWindow, thirdWindow, secondWindow].map(ObjectIdentifier.init))
    }

    /// 同じ文書から続けて開いた派生タブはクリック順に並ぶ(TASK-611。Safari / Chrome と同じ)。
    /// 記録するのは**最後の**派生タブだけなので、それが閉じられて居なくなれば次は起点の直後へ戻る
    /// (最後でない派生タブを閉じても記録は変わらない)。
    /// 記録は起点の ViewerWindowController が持つので、コントローラ付きの実ウィンドウで測る。
    @Test("afterSource で続けて開くとクリック順に並び、派生タブが消えれば起点の直後へ戻る")
    func afterSourceChainsSpawnedTabsInClickOrder() throws {
        let doc = URL(fileURLWithPath: "/mock/doc.md")
        let linkA = URL(fileURLWithPath: "/mock/a.md")
        let linkB = URL(fileURLWithPath: "/mock/b.md")
        let linkC = URL(fileURLWithPath: "/mock/c.md")
        let fixture = MockedViewerWindowManager(
            files: [doc, linkA, linkB, linkC], prefix: "ViewerWindowManagerTabTests"
        )
        defer { fixture.closeAll() }
        let docWindow = try #require(fixture.manager.openViewer(for: doc)?.window)
        func spawn(_ url: URL) throws -> NSWindow {
            try #require(
                fixture.manager.openViewer(
                    for: url, disposition: .newTab, relativeTo: docWindow, tabPlacement: .afterSource
                )?.window
            )
        }

        let windowA = try spawn(linkA)
        let windowB = try spawn(linkB)
        #expect(
            docWindow.tabGroup?.windows.map(ObjectIdentifier.init)
                == [docWindow, windowA, windowB].map(ObjectIdentifier.init)
        )

        try #require(fixture.manager.controllers[linkB.normalizedPathKey]?.first).close()
        let windowC = try spawn(linkC)

        #expect(
            docWindow.tabGroup?.windows.map(ObjectIdentifier.init)
                == [docWindow, windowC, windowA].map(ObjectIdentifier.init)
        )
    }

    @Test("起点ウィンドウが無ければ独立したウィンドウとして開く")
    func newTabWithoutSourceFallsBackToWindow() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file, disposition: .newTab, relativeTo: nil)

        #expect(fixture.manager.window(forPath: file.normalizedPathKey) != nil)
    }

    @Test("newWindow は起点ウィンドウを渡してもタブ結合しない")
    func newWindowNeverJoinsTabGroup() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newWindow, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        #expect(secondWindow?.tabGroup?.windows.contains(where: { $0 === firstWindow }) != true)
    }

    @Test("既に開いているファイルでも newWindow なら新しいウィンドウを開く")
    func newWindowOpensDuplicateForAlreadyOpenFile() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: file)
        let firstWindow = fixture.manager.window(forPath: file.normalizedPathKey)
        fixture.manager.openViewer(for: file, disposition: .newWindow, relativeTo: firstWindow)

        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 2)
        fixture.closeAll()
    }

    @Test("同じタブグループで既に開いているファイルの newTab は新規タブを作らず既存タブを選択する")
    func newTabActivatesExistingTabInSameGroup() {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: first)
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        fixture.manager.openViewer(for: second, disposition: .newTab, relativeTo: firstWindow)
        let secondWindow = fixture.manager.window(forPath: second.normalizedPathKey)

        let reused = fixture.manager.openViewer(for: first, disposition: .newTab, relativeTo: secondWindow)

        #expect(fixture.manager.controllers[first.normalizedPathKey]?.count == 1)
        #expect(reused?.window === firstWindow)
        #expect(firstWindow?.tabGroup?.selectedWindow === firstWindow)
    }

    @Test("別ウィンドウで開いているだけなら newTab は従来どおり起点のタブグループへ新しいタブを開く")
    func newTabOpensTabWhenFileIsOpenOnlyInAnotherWindow() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let other = URL(fileURLWithPath: "/mock/other.md")
        let fixture = MockedViewerWindowManager(files: [file, other], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file)
        let otherWindow = fixture.manager.openViewer(for: other)?.window

        fixture.manager.openViewer(for: file, disposition: .newTab, relativeTo: otherWindow)

        let opened = fixture.manager.controllers[file.normalizedPathKey] ?? []
        #expect(opened.count == 2)
        #expect(opened.last?.window?.tabGroup === otherWindow?.tabGroup)
    }

    /// スライド窓を起点にした cmd+クリック(TASK-615)。器の `tabbingMode = .disallowed` は
    /// **自動**タブ化しか止めないので、`addTabbedWindow` を通す `.newTab` の経路は開く側で倒す。
    /// 倒し損ねると、発表中のスライド窓に通常窓がタブとして吸い込まれる。
    @Test("スライド窓を起点にした newTab は独立した通常窓を開き、スライド窓のタブにならない")
    func newTabFromSlideWindowOpensIndependentWindow() throws {
        let first = URL(fileURLWithPath: "/mock/first.md")
        let second = URL(fileURLWithPath: "/mock/second.md")
        let fixture = MockedViewerWindowManager(files: [first, second], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }
        let slideWindow = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)?.window
        )

        let opened = try #require(
            fixture.manager.openViewer(for: second, disposition: .newTab, relativeTo: slideWindow)
        )

        #expect(opened.kind == .viewer)
        #expect(opened.window?.tabGroup?.windows.contains { $0 === slideWindow } != true)
    }

    /// 同じファイルでも同じこと(TASK-615)。TASK-613 でスライド窓が再利用候補から外れたため、
    /// ここは「スライド窓が前面化する」ではなく「通常窓が新しく開く」経路を通る。
    @Test("スライド窓を起点に同じファイルを newTab で開いても独立した通常窓になる")
    func newTabForSameFileFromSlideWindowOpensIndependentWindow() throws {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")
        defer { fixture.closeAll() }
        let slide = try #require(fixture.manager.openViewer(for: file, disposition: .slide))
        let slideWindow = try #require(slide.window)

        let opened = try #require(
            fixture.manager.openViewer(for: file, disposition: .newTab, relativeTo: slideWindow)
        )

        #expect(opened !== slide)
        #expect(opened.kind == .viewer)
        #expect(opened.window?.tabGroup?.windows.contains { $0 === slideWindow } != true)
    }

    @Test("Finder/CLI 由来の再オープン(currentTab)は重複ウィンドウを作らない")
    func currentTabReopenReusesExistingWindow() {
        let file = URL(fileURLWithPath: "/mock/only.md")
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ViewerWindowManagerTabTests")

        fixture.manager.openViewer(for: file)
        fixture.manager.openViewer(for: file)

        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 1)
        fixture.closeAll()
    }
}
