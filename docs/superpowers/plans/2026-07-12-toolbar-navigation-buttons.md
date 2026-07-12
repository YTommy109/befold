# 戻る・進むボタンのツールバー移設と行番号トグル統合 実装計画

<!-- derived-from ../specs/2026-07-12-toolbar-navigation-buttons-design.md -->

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 戻る・進むボタンをサイドバーからツールバー(プレビュー側)へ移設し、行番号トグルもツールバーへ統合して `ViewerTopBar` を廃止、あわせて Cmd+[ / Cmd+] のメニュー項目を追加する。

**Architecture:** NSToolbar(unified)に `NSToolbarItem.Identifier.sidebarTrackingSeparator`(システム標準・デリゲート実装不要)を挟み、戻る・進むアイテムをプレビュー領域左端へ配置する。既存の `HistoryButtonView`(長押し履歴メニュー付き NSButton)を SwiftUI ラッパーなしの自己完結 AppKit ボタンへ再構成して再利用する。履歴状態の変化は `SidebarNavigatorHost` プロトコルに `historyStateDidChange()` を追加して `ViewerWindowController` がツールバーへ反映する。

**Tech Stack:** Swift 6(strict concurrency)/ AppKit NSToolbar / SwiftUI(サイドバー・コンテンツ)/ Swift Testing

## Global Constraints

- ビルド・テストは `cd BefoldApp && swift build` / `swift test`(要 Xcode.app)
- テスト関数名は英語 camelCase、日本語説明は `@Test("...")` で付ける
- ローカライズは `befold/Resources/Localizable.xcstrings`(en / ja 両方必須。`LocalizationTests` が訳漏れを検出する)
- 文字列参照は `String(localized: "key", bundle: .l10n)`
- コミットは Conventional Commits + 日本語
- ツールバー・ボタン外観の視覚確認は GUI 層のため自動テスト対象外(タスク5で手動チェック)

---

### Task 1: HistoryButtonView を自己完結化し、サイドバーから戻る・進むを撤去する

**Files:**
- Modify: `BefoldApp/befold/Viewer/HistoryNavigationButton.swift`(全面書き換え後、`git mv` で `HistoryButtonView.swift` へリネーム)
- Modify: `BefoldApp/befold/Viewer/FileListView.swift:10,20-46`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:198-215`

**Interfaces:**
- Produces: `final class HistoryButtonView: NSButton` —
  `init(systemImage: String, accessibilityLabel: String, primaryOffset: Int, onNavigate: @escaping (Int) -> Void)` と
  `func updateState(isEnabled: Bool, entries: [HistoryEntry])`。Task 2 がツールバーアイテムの view として使う。
- 削除: `struct HistoryNavigationButton`(NSViewRepresentable)、`FileListView.onNavigateHistory`

- [ ] **Step 1: HistoryNavigationButton.swift を自己完結の AppKit ボタンへ書き換える**

ファイル全体を以下で置き換える。Coordinator の責務(primary 実行・履歴メニュー表示)をボタン自身へ移し、SwiftUI ラッパーを削除する。スタイルはサイドバー用の borderless からツールバー用の bordered(`.texturedRounded`)へ変える。

```swift
import AppKit

/// 戻る/進むのツールバーボタン。クリックで primary 移動(戻る/進む 1 段)、
/// 長押し・右クリック・Cmd/Ctrl+クリックで履歴メニューをポップアップする。
final class HistoryButtonView: NSButton {
    /// クリック時に移動する履歴オフセット(-1=戻る / +1=進む)。
    private var primaryOffset = -1
    /// 履歴メニューに表示するエントリ(現在位置に近い順)。
    private var entries: [HistoryEntry] = []
    private var onNavigate: ((Int) -> Void)?

    convenience init(
        systemImage: String,
        accessibilityLabel: String,
        primaryOffset: Int,
        onNavigate: @escaping (Int) -> Void
    ) {
        self.init(frame: .zero)
        self.primaryOffset = primaryOffset
        self.onNavigate = onNavigate
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.momentaryPushIn)
        image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: accessibilityLabel
        )
        isEnabled = false
    }

    /// 履歴状態の変化をボタンへ反映する。
    func updateState(isEnabled: Bool, entries: [HistoryEntry]) {
        self.isEnabled = isEnabled
        self.entries = entries
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }

        highlight(true)
        let deadline = Date(timeIntervalSinceNow: 0.3)
        var clickedInside = false
        var mouseUp = false
        while let next = window?.nextEvent(
            matching: [.leftMouseUp, .leftMouseDragged],
            until: deadline,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if next.type == .leftMouseUp {
                mouseUp = true
                let location = convert(next.locationInWindow, from: nil)
                clickedInside = bounds.contains(location)
                break
            }
        }
        highlight(false)

        if clickedInside {
            onNavigate?(primaryOffset)
        } else if !mouseUp {
            showMenu()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        showMenu()
    }

    private func showMenu() {
        guard !entries.isEmpty else { return }
        let menu = NSMenu()
        let direction = primaryOffset < 0 ? -1 : 1
        for (index, entry) in entries.enumerated() {
            let (title, icon) = Self.menuLabel(for: entry)
            let item = NSMenuItem(
                title: title,
                action: #selector(menuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.image = icon
            item.target = self
            item.tag = direction * (index + 1)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
    }

    private static func menuLabel(for entry: HistoryEntry) -> (String, NSImage) {
        if let file = entry.file {
            let dirName = entry.directory.lastPathComponent
            let title = "\(file.lastPathComponent) — \(dirName)"
            let icon = NSWorkspace.shared.icon(forFile: file.path)
            icon.size = NSSize(width: 16, height: 16)
            return (title, icon)
        } else {
            let title = entry.directory.lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: entry.directory.path)
            icon.size = NSSize(width: 16, height: 16)
            return (title, icon)
        }
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        onNavigate?(sender.tag)
    }
}
```

- [ ] **Step 2: ファイル名をクラス名に合わせてリネームする**

```bash
cd BefoldApp && git mv befold/Viewer/HistoryNavigationButton.swift befold/Viewer/HistoryButtonView.swift
```

- [ ] **Step 3: FileListView から戻る・進むボタンと onNavigateHistory を削除する**

`BefoldApp/befold/Viewer/FileListView.swift` で:

(a) L10 のプロパティ宣言を削除:

```swift
    var onNavigateHistory: ((Int) -> Void)?
```

(b) `header`(L20-73)から 2 つの `HistoryNavigationButton(...)...frame(width: 20, height: 20)` ブロック(L22-40)を削除する。ヘッダーの先頭は `Text(model.currentDirectory.lastPathComponent)` になる:

```swift
    private var header: some View {
        HStack {
            Text(model.currentDirectory.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
```

(以降のソートボタン・不可視ファイルボタンは変更なし)

- [ ] **Step 4: ViewerWindowController の FileListView 生成から引数を削除する**

`BefoldApp/befold/App/ViewerWindowController.swift:210` の 1 行を削除:

```swift
            onNavigateHistory: { [weak self] offset in self?.navigateHistory(by: offset) },
```

- [ ] **Step 5: ビルドと全テストが通ることを確認する**

Run: `cd BefoldApp && swift build && swift test`
Expected: ビルド成功、全テスト PASS(この時点で戻る・進むの GUI は一時的に消えるが、履歴ロジック・スワイプは無傷)

- [ ] **Step 6: コミット**

```bash
git add -A
git commit -m "refactor: HistoryButtonView を自己完結化しサイドバーから戻る・進むを撤去する"
```

---

### Task 2: ツールバーに戻る・進むアイテムと tracking separator を追加する

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`(識別子定数、NSToolbarDelegate、SidebarNavigatorHost 準拠)
- Modify: `BefoldApp/befold/App/SidebarNavigator.swift:6-17,240-243`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`(キーのリネーム)
- Create: `BefoldApp/befoldTests/ViewerWindowControllerToolbarTests.swift`

**Interfaces:**
- Consumes: Task 1 の `HistoryButtonView.init(systemImage:accessibilityLabel:primaryOffset:onNavigate:)` / `updateState(isEnabled:entries:)`
- Produces: ツールバー識別子 `NSToolbarItem.Identifier("historyBack")` / `NSToolbarItem.Identifier("historyForward")`(Task 3 のテストが既定並びの検証で参照)。
  `SidebarNavigatorHost` に `func historyStateDidChange()` を追加。

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerWindowControllerToolbarTests.swift` を新規作成:

```swift
import AppKit
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct ViewerWindowControllerToolbarTests {
    private func makeController(file: URL) -> ViewerWindowController {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerToolbarTests")
        return ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults
        )
    }

    @Test("既定アイテムは サイドバー開閉/仕切り/戻る/進む/可変スペース/モード切替 の順")
    func defaultItemsPlaceHistoryButtonsAfterTrackingSeparator() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        let identifiers = controller.toolbarDefaultItemIdentifiers(toolbar)

        #expect(identifiers == [
            .toggleSidebar, .sidebarTrackingSeparator,
            .init("historyBack"), .init("historyForward"),
            .flexibleSpace, .init("modeToggle"),
        ])
    }

    @Test("履歴が無い間、戻る・進むアイテムは無効")
    func historyItemsDisabledWithoutHistory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        for identifier in ["historyBack", "historyForward"] {
            let item = try #require(controller.toolbar(
                toolbar, itemForItemIdentifier: .init(identifier), willBeInsertedIntoToolbar: false
            ))
            let button = try #require(item.view as? HistoryButtonView)
            #expect(button.isEnabled == false, "\(identifier) は初期状態で無効のはず")
        }
    }

    @Test("ファイル切替で履歴ができると戻るアイテムが有効になる")
    func backItemEnabledAfterFileSwitch() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let fileB = try tmp.file(named: "b.mmd", contents: "graph TD;")
        let controller = makeController(file: fileA)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        controller.switchFile(to: fileB)

        let item = try #require(controller.toolbar(
            toolbar, itemForItemIdentifier: .init("historyBack"), willBeInsertedIntoToolbar: false
        ))
        let button = try #require(item.view as? HistoryButtonView)
        #expect(button.isEnabled == true)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerToolbarTests`
Expected: FAIL(`historyBack` アイテムが nil / 既定並びの不一致)

- [ ] **Step 3: ローカライズキーをリネームする**

`BefoldApp/befold/Resources/Localizable.xcstrings`(JSON)で、キー `"sidebar.back"` を `"toolbar.back"` に、`"sidebar.forward"` を `"toolbar.forward"` に書き換える(値 en "Back"/ja "戻る"、en "Forward"/ja "進む" はそのまま。周辺エントリと同じ構造を維持する)。

- [ ] **Step 4: SidebarNavigatorHost に履歴変化通知を追加する**

`BefoldApp/befold/App/SidebarNavigator.swift` のプロトコル(L6-17)に追加:

```swift
    /// 戻る/進む履歴の状態が変化した。AppKit 側 UI(ツールバー)の更新契機。
    func historyStateDidChange()
```

`refreshHistoryState()`(L240-243)の末尾に通知を追加:

```swift
    /// 履歴状態をサイドバー(FileListModel)とホスト(ツールバー)へ反映する。
    private func refreshHistoryState() {
        fileListModel.backHistory = history.backEntries()
        fileListModel.forwardHistory = history.forwardEntries()
        host?.historyStateDidChange()
    }
```

- [ ] **Step 5: ViewerWindowController にツールバーアイテムを実装する**

`BefoldApp/befold/App/ViewerWindowController.swift` で:

(a) 識別子定数を追加(L35 の `modeToggleItemIdentifier` の直後):

```swift
    private static let backItemIdentifier = NSToolbarItem.Identifier("historyBack")
    private static let forwardItemIdentifier = NSToolbarItem.Identifier("historyForward")
```

(b) NSToolbarDelegate 拡張(L640-)の `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` 冒頭の guard の前に分岐を追加:

```swift
        if itemIdentifier == Self.backItemIdentifier || itemIdentifier == Self.forwardItemIdentifier {
            return makeHistoryToolbarItem(itemIdentifier)
        }
        guard itemIdentifier == Self.modeToggleItemIdentifier else { return nil }
```

(c) 同じ拡張内にアイテム生成と状態反映を追加:

```swift
    /// 戻る/進むのツールバーアイテムを生成する。生成時点の履歴状態を初期反映する。
    private func makeHistoryToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let isBack = identifier == Self.backItemIdentifier
        let label = isBack
            ? String(localized: "toolbar.back", bundle: .l10n)
            : String(localized: "toolbar.forward", bundle: .l10n)
        let button = HistoryButtonView(
            systemImage: isBack ? "chevron.left" : "chevron.right",
            accessibilityLabel: label,
            primaryOffset: isBack ? -1 : 1,
            onNavigate: { [weak self] offset in self?.navigateHistory(by: offset) }
        )
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.view = button
        updateHistoryToolbarItem(item)
        return item
    }

    /// 戻る/進むアイテム 1 つへ現在の履歴状態を反映する。
    private func updateHistoryToolbarItem(_ item: NSToolbarItem) {
        guard let button = item.view as? HistoryButtonView else { return }
        if item.itemIdentifier == Self.backItemIdentifier {
            button.updateState(isEnabled: fileListModel.canGoBack, entries: fileListModel.backHistory)
        } else {
            button.updateState(isEnabled: fileListModel.canGoForward, entries: fileListModel.forwardHistory)
        }
    }
```

(d) 既定・許可アイテム並び(L672-678)を差し替え:

```swift
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            .flexibleSpace, Self.modeToggleItemIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            Self.modeToggleItemIdentifier, .flexibleSpace, .space,
        ]
    }
```

(e) `SidebarNavigatorHost` 準拠の拡張(L395-405)に通知の実装を追加:

```swift
    /// 履歴状態の変化をツールバーの戻る/進むアイテムへ反映する。
    func historyStateDidChange() {
        window?.toolbar?.items
            .filter {
                $0.itemIdentifier == Self.backItemIdentifier
                    || $0.itemIdentifier == Self.forwardItemIdentifier
            }
            .forEach { updateHistoryToolbarItem($0) }
    }
```

- [ ] **Step 6: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerToolbarTests`
Expected: PASS

- [ ] **Step 7: 全テストが通ることを確認する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS(`LocalizationTests` がキーリネーム後も通ること)

- [ ] **Step 8: コミット**

```bash
git add -A
git commit -m "feat: 戻る・進むボタンをツールバーのプレビュー側へ移設する"
```

---

### Task 3: 行番号トグルをツールバーへ統合し ViewerTopBar を廃止する

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`(識別子・アイテム生成・状態反映・呼び出し箇所)
- Delete: `BefoldApp/befold/Viewer/ViewerTopBar.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift:32-36`
- Modify: `BefoldApp/befoldTests/ViewerWindowControllerToolbarTests.swift`

**Interfaces:**
- Consumes: Task 2 の既定アイテム並び(このタスクで `lineNumbers` を挿入)
- Produces: ツールバー識別子 `NSToolbarItem.Identifier("lineNumbers")`
- 削除: `struct ViewerTopBar`

- [ ] **Step 1: 失敗するテストを書く**

`ViewerWindowControllerToolbarTests.swift` に追加し、既存の既定並びテストの期待値を更新する。

(a) 既存テスト `defaultItemsPlaceHistoryButtonsAfterTrackingSeparator` の期待配列を差し替え:

```swift
        #expect(identifiers == [
            .toggleSidebar, .sidebarTrackingSeparator,
            .init("historyBack"), .init("historyForward"),
            .flexibleSpace, .init("lineNumbers"), .init("modeToggle"),
        ])
```

(b) 新規テストを追加:

```swift
    @Test("行番号アイテムはコード表示中のみ有効")
    func lineNumbersItemEnabledOnlyForCodeContent() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let codeFile = try tmp.file(named: "a.swift", contents: "let x = 1")
        let previewFile = try tmp.file(named: "b.mmd", contents: "graph TD;")

        let codeController = makeController(file: codeFile)
        defer { codeController.close() }
        let codeToolbar = try #require(codeController.window?.toolbar)
        let codeItem = try #require(codeController.toolbar(
            codeToolbar, itemForItemIdentifier: .init("lineNumbers"), willBeInsertedIntoToolbar: false
        ))
        let codeButton = try #require(codeItem.view as? NSButton)
        #expect(codeButton.isEnabled == true)

        let previewController = makeController(file: previewFile)
        defer { previewController.close() }
        let previewToolbar = try #require(previewController.window?.toolbar)
        let previewItem = try #require(previewController.toolbar(
            previewToolbar, itemForItemIdentifier: .init("lineNumbers"), willBeInsertedIntoToolbar: false
        ))
        let previewButton = try #require(previewItem.view as? NSButton)
        #expect(previewButton.isEnabled == false)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerToolbarTests`
Expected: FAIL(`lineNumbers` アイテムが nil / 既定並びの不一致)

- [ ] **Step 3: ViewerWindowController に行番号アイテムを実装する**

`BefoldApp/befold/App/ViewerWindowController.swift` で:

(a) 識別子定数を追加(Task 2 で追加した定数の直後):

```swift
    private static let lineNumbersItemIdentifier = NSToolbarItem.Identifier("lineNumbers")
```

(b) `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` に分岐を追加(履歴アイテムの分岐の直後):

```swift
        if itemIdentifier == Self.lineNumbersItemIdentifier {
            return makeLineNumbersToolbarItem()
        }
```

(c) NSToolbarDelegate 拡張内にアイテム生成を追加:

```swift
    /// 行番号トグルのツールバーアイテムを生成する。常時表示し、
    /// コード系コンテンツ表示中(showsCodeContent)以外は無効にする。
    private func makeLineNumbersToolbarItem() -> NSToolbarItem {
        let label = String(localized: "menu.view.showLineNumbers", bundle: .l10n)
        let button = NSButton(
            image: NSImage(systemSymbolName: "list.number", accessibilityDescription: label)!,
            target: self,
            action: #selector(toggleLineNumbers(_:))
        )
        button.bezelStyle = .texturedRounded
        button.setButtonType(.pushOnPushOff)
        let item = NSToolbarItem(itemIdentifier: Self.lineNumbersItemIdentifier)
        item.label = label
        item.view = button
        updateLineNumbersToolbarItem(item)
        return item
    }

    /// 行番号アイテムの有効/無効・オンオフ表示・ツールチップを現在の表示状態に合わせて更新する。
    /// - Parameter item: 更新対象。省略時は window.toolbar から検索する
    ///   (生成中でまだ toolbar.items に含まれないアイテムを更新する場合は明示的に渡すこと)。
    private func updateLineNumbersToolbarItem(_ item: NSToolbarItem? = nil) {
        guard let item = item ?? window?.toolbar?.items.first(where: {
            $0.itemIdentifier == Self.lineNumbersItemIdentifier
        }), let button = item.view as? NSButton else { return }
        button.isEnabled = store.showsCodeContent
        button.state = store.showLineNumbers ? .on : .off
        item.toolTip = store.showLineNumbers
            ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
            : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
    }
```

(d) 既定・許可アイテム並びへ挿入(Task 2 の配列を更新):

```swift
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            .flexibleSpace, Self.lineNumbersItemIdentifier, Self.modeToggleItemIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            Self.lineNumbersItemIdentifier, Self.modeToggleItemIdentifier,
            .flexibleSpace, .space,
        ]
    }
```

(e) 状態変化時の更新を既存経路へ足す。

`toggleLineNumbers(_:)`(L496-498)を:

```swift
    /// View > Toggle Line Numbers / ツールバーの行番号ボタン。行番号表示の有無を切り替える。
    @objc func toggleLineNumbers(_ sender: Any?) {
        store.showLineNumbers.toggle()
        updateLineNumbersToolbarItem()
    }
```

`applySourceMode(_:)`(L525-531)末尾の `updateModeToggleAppearance()` の直後に 1 行追加:

```swift
        updateModeToggleAppearance()
        updateLineNumbersToolbarItem()
```

`init` 内の `store.onContentReloaded`(L167-169)を:

```swift
        store.onContentReloaded = { [weak self] in
            self?.updateModeToggleAppearance()
            self?.updateLineNumbersToolbarItem()
        }
```

- [ ] **Step 4: ViewerTopBar を削除する**

```bash
cd BefoldApp && git rm befold/Viewer/ViewerTopBar.swift
```

`BefoldApp/befold/Viewer/ViewerContentView.swift` の `body`(L32-36)から条件分岐を削除する。`VStack(spacing: 0)` の中身が `ZStack` だけになるため、`VStack` ごと外して `ZStack` を直下に置く:

```swift
    var body: some View {
        // ViewerWebView は常に生かしておき(ビュー同一性を維持)、非対応時は
        // 上に UnsupportedFileView を重ねる。テキスト↔バイナリの切替で WKWebView が
        // 破棄・再生成されて白フラッシュや stale な initialZoom が起きるのを防ぐ。
        ZStack {
            ViewerWebView(
```

(ZStack の中身・閉じ括弧の対応は既存のまま。外側 VStack の閉じ括弧を 1 つ削る)

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerToolbarTests`
Expected: PASS

- [ ] **Step 6: 全テストが通ることを確認する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS

- [ ] **Step 7: コミット**

```bash
git add -A
git commit -m "feat: 行番号トグルをツールバーへ統合し ViewerTopBar を廃止する"
```

---

### Task 4: View メニューに戻る・進む(⌘[ / ⌘])を追加する

**Files:**
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift:186-204`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`(ハンドラと validateMenuItem)
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`(キー追加)
- Modify: `BefoldApp/befoldTests/MainMenuBuilderTests.swift:72-93`
- Modify: `BefoldApp/befoldTests/ViewerWindowControllerTests.swift`

**Interfaces:**
- Produces: `@objc func goBack(_ sender: Any?)` / `@objc func goForward(_ sender: Any?)`(ViewerWindowController)、
  ローカライズキー `menu.view.goBack` / `menu.view.goForward`

- [ ] **Step 1: 失敗するテストを書く**

(a) `MainMenuBuilderTests.swift` の `menuItemHasKeyEquivalent` の arguments 配列(L72-93)に 2 エントリ追加(toggleSidebar のエントリの直後):

```swift
        (
            submenuKey: "menu.view.title",
            selector: #selector(ViewerWindowController.goBack(_:)),
            key: "[", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // View メニューに Back(⌘[) がある
        (
            submenuKey: "menu.view.title",
            selector: #selector(ViewerWindowController.goForward(_:)),
            key: "]", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // View メニューに Forward(⌘]) がある
```

(b) `ViewerWindowControllerTests.swift` に validateMenuItem のテストを追加(既存の履歴系テスト群の近くに):

```swift
    @Test("戻る/進むメニューは対応する履歴があるときだけ有効")
    func goBackAndForwardMenuValidation() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let fileB = try tmp.file(named: "b.mmd", contents: "graph TD;")
        let controller = makeController(file: fileA)
        defer { controller.close() }
        let backItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.goBack(_:)), keyEquivalent: ""
        )
        let forwardItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.goForward(_:)), keyEquivalent: ""
        )

        #expect(controller.validateMenuItem(backItem) == false)
        #expect(controller.validateMenuItem(forwardItem) == false)

        controller.switchFile(to: fileB)
        #expect(controller.validateMenuItem(backItem) == true)
        #expect(controller.validateMenuItem(forwardItem) == false)

        controller.navigateHistory(by: -1)
        #expect(controller.validateMenuItem(backItem) == false)
        #expect(controller.validateMenuItem(forwardItem) == true)
    }
```

注: `goBack(_:)` が未定義のこの時点ではコンパイルエラーになる。それが Step 2 の「失敗」に相当する。

- [ ] **Step 2: テストが失敗する(コンパイルエラーになる)ことを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`
Expected: FAIL(`goBack` unresolved のコンパイルエラー)

- [ ] **Step 3: ローカライズキーを追加する**

`BefoldApp/befold/Resources/Localizable.xcstrings` に周辺エントリと同じ構造で追加:

- `menu.view.goBack`: en `Back` / ja `戻る`
- `menu.view.goForward`: en `Forward` / ja `進む`

- [ ] **Step 4: ハンドラと validateMenuItem を実装する**

`BefoldApp/befold/App/ViewerWindowController.swift` の Menu Actions 拡張内(`toggleSourceView` の近く)に追加:

```swift
    /// View > Back。ファイル履歴を 1 つ戻る。
    @objc func goBack(_ sender: Any?) {
        navigateHistory(by: -1)
    }

    /// View > Forward。ファイル履歴を 1 つ進む。
    @objc func goForward(_ sender: Any?) {
        navigateHistory(by: 1)
    }
```

`validateMenuItem(_:)`(L563-581)の `toggleLineNumbers` 分岐の直後に追加:

```swift
        if menuItem.action == #selector(goBack(_:)) {
            return fileListModel.canGoBack
        }
        if menuItem.action == #selector(goForward(_:)) {
            return fileListModel.canGoForward
        }
```

- [ ] **Step 5: View メニューに項目を追加する**

`BefoldApp/befold/App/MainMenuBuilder.swift` の `makeViewMenuItem()` で、toggleSidebar ブロック(L198-203)の直後・`menu.addItem(.separator())`(L204)の前に追加:

```swift
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.view.goBack", bundle: .l10n),
            action: #selector(ViewerWindowController.goBack(_:)),
            keyEquivalent: "["
        )
        menu.addItem(
            withTitle: String(localized: "menu.view.goForward", bundle: .l10n),
            action: #selector(ViewerWindowController.goForward(_:)),
            keyEquivalent: "]"
        )
```

- [ ] **Step 6: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests && swift test --filter ViewerWindowControllerTests`
Expected: PASS

- [ ] **Step 7: 全テストが通ることを確認する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS

- [ ] **Step 8: コミット**

```bash
git add -A
git commit -m "feat: View メニューに戻る・進む(⌘[ / ⌘])を追加する"
```

---

### Task 5: 手動チェック(GUI 層)

**Files:** なし(検証のみ)

- [ ] **Step 1: アプリをビルドして起動する**

Run: `/run` スキル、または `cd BefoldApp && swift build && xcodegen generate && xcodebuild build -scheme befold`(既存の起動手順に従う)

- [ ] **Step 2: 以下を目視確認する**

1. ツールバー並び: サイドバー開閉 ┃ 戻る・進む … 行番号・モード切替
2. サイドバーを開閉したとき、仕切りが分割線に追従し、戻る・進むが常にプレビュー領域左端に見える
3. 戻る・進む: クリックで 1 段移動、長押し・右クリックで履歴メニューが出る、履歴が無いときは無効
4. Cmd+[ / Cmd+] で戻る・進むが動き、履歴が無いときメニューが無効
5. 行番号ボタン: ソース/コード表示中のみ有効、クリックで on/off、Cmd+L・View メニューと状態が同期
6. プレビュー⇄ソース切替時にコンテンツ上部のバーが出没しない(ViewerTopBar 廃止の確認)
7. トラックパッド水平スワイプの戻る/進むが従来どおり動く
8. サイドバーヘッダーにボタンの残骸がなく、ディレクトリ名から始まる

- [ ] **Step 3: 問題がなければ完了。問題があれば該当タスクへ戻って修正する**
