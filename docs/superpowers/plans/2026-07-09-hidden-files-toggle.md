# 不可視ファイル表示トグル Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サイドバーの不可視ファイル(ドットファイル)表示/非表示を、`Cmd+.`・View メニュー・サイドバーのアイコンボタンの3経路から切り替えられるようにする。デフォルトは非表示、選択は `UserDefaults` に永続化し、全ウィンドウへ即座に連動させる。

**Architecture:** `HiddenFilesPreference`(新規、`ZoomStore` と同型の永続化専用クラス)を `AppDelegate` が1つ生成して `ViewerWindowManager` に注入し、新規ウィンドウ生成のたびに同一インスタンスを `ViewerWindowController` → `SidebarNavigator` へ渡す。切り替えは `ViewerWindowManager.toggleHiddenFiles()` に一本化し、`hiddenFilesPreference` をトグルした後、開いている全 `ViewerWindowController` の `sidebar.refreshFileList()` を呼んで即座に再読み込みする。`DirectoryLister.listEntries` に `showHiddenFiles: Bool` パラメータを追加し、`FileManager` の `.skipsHiddenFiles` オプションを条件分岐する。

**Tech Stack:** Swift 6 (strict concurrency) / AppKit + SwiftUI / Swift Testing / XcodeGen

## Global Constraints

- Swift 6 strict concurrency(`SWIFT_STRICT_CONCURRENCY: complete`)。共有状態を扱うクラスは `@MainActor` を付与する。
- テスト関数名は英語 camelCase。日本語の説明が必要なら `@Test("日本語の説明")` の表示名で付ける。
- コミットメッセージは Conventional Commits + 日本語(例: `feat: 不可視ファイル表示の永続化ストアを追加する`)。
- デフォルトは不可視ファイル非表示(`showHiddenFiles == false`)。
- キーボードショートカット: `Cmd+.`
- `UserDefaults` キー: `"ShowHiddenFiles"`(`HiddenFilesPreference` が管理)。
- 表示状態は全ウィンドウで共有し、いずれかの操作経路で切り替えると即座に全ウィンドウのサイドバーへ反映する。
- テストは既存ストア系テスト(`ZoomStoreTests` など)と同様、`makeIsolatedDefaults(prefix:)` で隔離した `UserDefaults` を使い、実行環境の `UserDefaults.standard` を汚染しない。

---

## File Structure

- Create: `BefoldApp/befold/App/HiddenFilesPreference.swift` — 不可視ファイル表示設定の永続化専用クラス
- Create: `BefoldApp/befoldTests/HiddenFilesPreferenceTests.swift`
- Modify: `BefoldApp/befold/Viewer/DirectoryLister.swift` — `listEntries` に `showHiddenFiles` パラメータ追加
- Modify: `BefoldApp/befoldTests/DirectoryListerTests.swift`
- Modify: `BefoldApp/befold/Viewer/FileListModel.swift` — `showHiddenFiles` プロパティ追加
- Modify: `BefoldApp/befold/App/SidebarNavigator.swift` — `hiddenFilesPreference` を保持し `listEntries` 呼び出しへ反映
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift` — `hiddenFilesPreference` 注入、初期一覧取得、`onToggleHiddenFiles` コールバック
- Modify: `BefoldApp/befoldTests/ViewerWindowControllerTests.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowManager.swift` — `hiddenFilesPreference` 注入、`toggleHiddenFiles()` / `refreshAllSidebars()`
- Modify: `BefoldApp/befoldTests/ViewerWindowManagerTests.swift`
- Modify: `BefoldApp/befold/App/AppDelegate.swift` — `toggleHiddenFiles(_:)` アクション、`NSMenuItemValidation`
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift` — View メニュー項目追加
- Modify: `BefoldApp/befoldTests/MainMenuBuilderTests.swift`
- Modify: `BefoldApp/befold/Viewer/FileListView.swift` — サイドバーのアイコンボタン追加
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings` — メニュー・ツールチップ文言追加

---

### Task 1: `HiddenFilesPreference`(永続化専用クラス)

**Files:**
- Create: `BefoldApp/befold/App/HiddenFilesPreference.swift`
- Test: `BefoldApp/befoldTests/HiddenFilesPreferenceTests.swift`

**Interfaces:**
- Produces: `@MainActor final class HiddenFilesPreference { init(defaults: UserDefaults = .standard); var showHiddenFiles: Bool { get set } }`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/HiddenFilesPreferenceTests.swift` を新規作成する。

```swift
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct HiddenFilesPreferenceTests {
    @Test("デフォルトは非表示(false)")
    func defaultsToHiddenWhenUnsaved() {
        let preference = HiddenFilesPreference(defaults: makeIsolatedDefaults(prefix: "HiddenFilesPreferenceTests"))

        #expect(preference.showHiddenFiles == false)
    }

    @Test("トグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる")
    func togglePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults(prefix: "HiddenFilesPreferenceTests")

        HiddenFilesPreference(defaults: defaults).showHiddenFiles = true

        #expect(HiddenFilesPreference(defaults: defaults).showHiddenFiles == true)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter HiddenFilesPreferenceTests`
Expected: FAIL(`HiddenFilesPreference` が存在しないためビルドエラー)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/App/HiddenFilesPreference.swift` を新規作成する。

```swift
import Foundation

/// 不可視ファイル(ドットファイル)表示のON/OFFを UserDefaults に永続化する。
/// ZoomStore と同じ「注入して共有する」パターンに倣い、全ウィンドウで
/// 同一インスタンスを共有することでアプリ全体・全ウィンドウ共通の状態にする。
@MainActor
final class HiddenFilesPreference {
    private let defaults: UserDefaults
    private static let showHiddenFilesKey = "ShowHiddenFiles"

    var showHiddenFiles: Bool {
        didSet {
            defaults.set(showHiddenFiles, forKey: Self.showHiddenFilesKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showHiddenFiles = defaults.bool(forKey: Self.showHiddenFilesKey)
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter HiddenFilesPreferenceTests`
Expected: PASS(2 tests)

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/HiddenFilesPreference.swift BefoldApp/befoldTests/HiddenFilesPreferenceTests.swift
git commit -m "feat: 不可視ファイル表示の永続化ストアを追加する"
```

---

### Task 2: `DirectoryLister.listEntries` に `showHiddenFiles` パラメータを追加する

**Files:**
- Modify: `BefoldApp/befold/Viewer/DirectoryLister.swift:20`
- Test: `BefoldApp/befoldTests/DirectoryListerTests.swift`

**Interfaces:**
- Consumes: なし(このタスクは自己完結)
- Produces: `DirectoryLister.listEntries(in: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false) -> [FileListEntry]`(デフォルト `false` のため既存呼び出し元は変更不要)

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/DirectoryListerTests.swift` の `listEntriesHasParentBelowHome` テストの直後に以下を追加する(114行目付近、`listEntriesAlphabeticalSort` の後)。

```swift
    @Test("listEntries は showHiddenFiles が true のとき不可視ファイル・フォルダーも含める")
    func listEntriesIncludesHiddenWhenShowHiddenFilesIsTrue() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "")
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent(".hiddenDir"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "visible.mmd", contents: "")

        let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst, showHiddenFiles: true)

        let names = entries.map(\.url.lastPathComponent)
        #expect(names.contains(".hidden.mmd"))
        #expect(names.contains(".hiddenDir"))
        #expect(names.contains("visible.mmd"))
    }

    @Test("listEntries は showHiddenFiles を省略すると不可視ファイル・フォルダーを除外する")
    func listEntriesExcludesHiddenByDefault() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "")
        _ = try tmp.file(named: "visible.mmd", contents: "")

        let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)

        let names = entries.map(\.url.lastPathComponent)
        #expect(!names.contains(".hidden.mmd"))
        #expect(names.contains("visible.mmd"))
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter DirectoryListerTests`
Expected: FAIL(`listEntriesIncludesHiddenWhenShowHiddenFilesIsTrue` が `showHiddenFiles:` 引数なしのシグネチャでコンパイルエラー)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/Viewer/DirectoryLister.swift:20-27` を以下に置き換える。

```swift
    static func listEntries(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false
    ) -> [FileListEntry] {
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else {
            return []
        }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter DirectoryListerTests`
Expected: PASS(全 `DirectoryListerTests` が通る。既存テストもデフォルト引数のまま変更不要)

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Viewer/DirectoryLister.swift BefoldApp/befoldTests/DirectoryListerTests.swift
git commit -m "feat: DirectoryLister.listEntries に showHiddenFiles パラメータを追加する"
```

---

### Task 3: `FileListModel` に `showHiddenFiles` プロパティを追加する

**Files:**
- Modify: `BefoldApp/befold/Viewer/FileListModel.swift:16`

**Interfaces:**
- Produces: `FileListModel.showHiddenFiles: Bool`(`@Observable` により変更が SwiftUI 再描画をトリガーする。デフォルト `false`。`SidebarNavigator` が現在の `HiddenFilesPreference` の値と同期させる、UI からの直接編集は行わない)

このプロパティはデフォルト値を持つため既存の `init` はそのまま変更不要(既存テスト・呼び出し元への影響なし)。

- [ ] **Step 1: 実装を書く**

`BefoldApp/befold/Viewer/FileListModel.swift:16` の `var sortOrder: SortOrder` の直後に追加する。

```swift
    var sortOrder: SortOrder
    /// サイドバーのアイコンボタン・メニュー・ショートカットの見た目に使う現在値。
    /// 永続化・真実の源は HiddenFilesPreference。SidebarNavigator が
    /// refreshFileList()/navigateToFolder(_:) のたびに同期する。
    var showHiddenFiles: Bool = false
```

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功(既存テストへの影響がないことは Task 4 で確認する)

- [ ] **Step 3: コミット**

```bash
git add BefoldApp/befold/Viewer/FileListModel.swift
git commit -m "feat: FileListModel に showHiddenFiles プロパティを追加する"
```

---

### Task 4: `SidebarNavigator` / `ViewerWindowController` へ `HiddenFilesPreference` を配線する

**Files:**
- Modify: `BefoldApp/befold/App/SidebarNavigator.swift:34-40,50-62,90-116`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:52-60`
- Test: `BefoldApp/befoldTests/ViewerWindowControllerTests.swift`

**Interfaces:**
- Consumes: `HiddenFilesPreference`(Task 1)、`DirectoryLister.listEntries(in:sortOrder:showHiddenFiles:)`(Task 2)、`FileListModel.showHiddenFiles`(Task 3)
- Produces:
  - `SidebarNavigator.init(currentDirectory: URL, entries: [FileListEntry], selection: URL?, hiddenFilesPreference: HiddenFilesPreference)`(新規必須引数)
  - `ViewerWindowController.init(fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard, hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(), forceSidebarVisible: Bool = false)`(デフォルト値付きのため既存呼び出し元は変更不要)

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerWindowControllerTests.swift` の `noPerFileFrameAutosave` テストの直前(24行目付近)に追加する。

```swift
    @Test("hiddenFilesPreference.showHiddenFiles が true のときサイドバーに不可視ファイルが含まれる")
    func sidebarIncludesHiddenFilesWhenPreferenceIsOn() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let preference = HiddenFilesPreference(defaults: defaults)
        preference.showHiddenFiles = true

        let controller = ViewerWindowController(
            fileURL: visible,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults,
            hiddenFilesPreference: preference
        )
        defer { controller.close() }

        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains(".hidden.mmd"))
        #expect(controller.fileListModel.showHiddenFiles)
    }

    @Test("hiddenFilesPreference.showHiddenFiles が false(デフォルト)のとき不可視ファイルは含まれない")
    func sidebarExcludesHiddenFilesWhenPreferenceIsOff() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let preference = HiddenFilesPreference(defaults: defaults)

        let controller = ViewerWindowController(
            fileURL: visible,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults,
            hiddenFilesPreference: preference
        )
        defer { controller.close() }

        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(!names.contains(".hidden.mmd"))
        #expect(!controller.fileListModel.showHiddenFiles)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerTests`
Expected: FAIL(`ViewerWindowController.init` に `hiddenFilesPreference:` 引数が存在せずコンパイルエラー)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/App/SidebarNavigator.swift:22-45` を以下に置き換える(`hiddenFilesPreference` プロパティと `init` の変更)。

```swift
@MainActor
final class SidebarNavigator {
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    let fileListModel: FileListModel
    /// このタブの戻る/進むナビゲーション履歴(メモリ内のみ)。
    let history = NavigationHistory()
    /// 不可視ファイル表示設定。全ウィンドウで共有される単一の真実の源を都度参照する。
    private let hiddenFilesPreference: HiddenFilesPreference

    /// ファイル切替・現在ファイル参照の委譲先。循環参照を避けるため weak。
    private weak var host: SidebarNavigatorHost?

    // MARK: - Initialization

    init(
        currentDirectory: URL, entries: [FileListEntry], selection: URL?,
        hiddenFilesPreference: HiddenFilesPreference
    ) {
        self.hiddenFilesPreference = hiddenFilesPreference
        fileListModel = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection
        )
        fileListModel.showHiddenFiles = hiddenFilesPreference.showHiddenFiles
    }
```

`BefoldApp/befold/App/SidebarNavigator.swift:50-62` の `refreshFileList()` を以下に置き換える。

```swift
    func refreshFileList() {
        guard let host else { return }
        let showHiddenFiles = hiddenFilesPreference.showHiddenFiles
        var entries = DirectoryLister.listEntries(
            in: fileListModel.currentDirectory,
            sortOrder: fileListModel.sortOrder,
            showHiddenFiles: showHiddenFiles
        )
        ensureCurrentFile(in: &entries, currentFile: host.currentFileURL)
        fileListModel.entries = entries
        fileListModel.showHiddenFiles = showHiddenFiles
        let matched = matchingEntryURL(for: host.currentFileURL)
        if fileListModel.selection != matched {
            fileListModel.selection = matched
        }
    }
```

`BefoldApp/befold/App/SidebarNavigator.swift:97-99`(`navigateToFolder(_:)` 内)を以下に置き換える。

```swift
        fileListModel.entries = DirectoryLister.listEntries(
            in: url, sortOrder: fileListModel.sortOrder, showHiddenFiles: hiddenFilesPreference.showHiddenFiles
        )
        fileListModel.showHiddenFiles = hiddenFilesPreference.showHiddenFiles
```

`BefoldApp/befold/App/ViewerWindowController.swift:52-60` を以下に置き換える。

```swift
    init(
        fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        forceSidebarVisible: Bool = false
    ) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
        self.defaults = defaults
        self.hiddenFilesPreference = hiddenFilesPreference
        self.forceSidebarVisible = forceSidebarVisible
        store = ViewerStore()
        let parentDir = fileURL.deletingLastPathComponent()
        let entries = DirectoryLister.listEntries(
            in: parentDir, sortOrder: .foldersFirst, showHiddenFiles: hiddenFilesPreference.showHiddenFiles
        )
        sidebar = SidebarNavigator(
            currentDirectory: parentDir, entries: entries, selection: fileURL,
            hiddenFilesPreference: hiddenFilesPreference
        )
```

`BefoldApp/befold/App/ViewerWindowController.swift:13-16` の格納プロパティ群に `hiddenFilesPreference` を追加する。

```swift
    private let defaults: UserDefaults
    private let store: ViewerStore
    private let zoomStore: ZoomStore
    private let hiddenFilesPreference: HiddenFilesPreference
    private let forceSidebarVisible: Bool
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerTests`
Expected: PASS(新規2テストを含め全 `ViewerWindowControllerTests` が通る)

Run: `cd BefoldApp && swift test --filter SidebarNavigatorIntegrationTests`
Expected: PASS(デフォルト引数のため既存テストは変更不要)

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/SidebarNavigator.swift BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befoldTests/ViewerWindowControllerTests.swift
git commit -m "feat: SidebarNavigator と ViewerWindowController に HiddenFilesPreference を配線する"
```

---

### Task 5: `ViewerWindowManager` に `toggleHiddenFiles()` / `refreshAllSidebars()` を追加する

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowManager.swift:6-16,34-38`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`(`onToggleHiddenFiles` コールバック追加)
- Test: `BefoldApp/befoldTests/ViewerWindowManagerTests.swift`

**Interfaces:**
- Consumes: `HiddenFilesPreference`(Task 1)、`ViewerWindowController.hiddenFilesPreference` 経由の配線(Task 4)
- Produces:
  - `ViewerWindowManager.init(sessionStore:zoomStore:recentDocumentsStore:hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference())`(デフォルト値付き)
  - `ViewerWindowManager.toggleHiddenFiles()`
  - `ViewerWindowManager.refreshAllSidebars()`
  - `ViewerWindowController.onToggleHiddenFiles: (() -> Void)?`(既存の `onClose`/`onRename` と同型のコールバックプロパティ)

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerWindowManagerTests.swift:9-17` の `makeManager` ヘルパーを以下に置き換える。

```swift
    private func makeManager(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
    ) -> ViewerWindowManager {
        ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            zoomStore: ZoomStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            hiddenFilesPreference: HiddenFilesPreference(defaults: defaults)
        )
    }
```

同ファイルの `windowForPathReturnsOpenWindow` テストの直後(109行目付近)に追加する。

```swift
    @Test("toggleHiddenFiles は状態を反転し開いているサイドバーへ反映する")
    func toggleHiddenFilesRefreshesOpenSidebar() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let manager = makeManager()

        manager.openViewer(for: visible)
        let controller = try #require(manager.controllers[visible.normalizedPathKey])
        #expect(!controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))

        manager.toggleHiddenFiles()

        #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("toggleHiddenFiles は複数の開いているウィンドウすべてへ同時に反映する")
    func toggleHiddenFilesAffectsAllOpenWindows() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)

        manager.toggleHiddenFiles()

        for controller in manager.controllers.values {
            #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("ウィンドウのアイコンボタン操作(onToggleHiddenFiles)でも全ウィンドウが同期する")
    func onToggleHiddenFilesCallbackTogglesAllWindows() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)
        let first = try #require(manager.controllers[file1.normalizedPathKey])

        first.onToggleHiddenFiles?()

        for controller in manager.controllers.values {
            #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }
        manager.controllers.values.forEach { $0.close() }
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowManagerTests`
Expected: FAIL(`ViewerWindowManager.init` に `hiddenFilesPreference:` 引数がなくコンパイルエラー、`toggleHiddenFiles()` / `onToggleHiddenFiles` も未定義)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/App/ViewerWindowManager.swift:6-16` を以下に置き換える。

```swift
@MainActor
final class ViewerWindowManager {
    private(set) var controllers: [String: ViewerWindowController] = [:]
    private let sessionStore: SessionStore
    private let zoomStore: ZoomStore
    private let recentDocumentsStore: RecentDocumentsStore
    private let hiddenFilesPreference: HiddenFilesPreference

    init(
        sessionStore: SessionStore, zoomStore: ZoomStore, recentDocumentsStore: RecentDocumentsStore,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference()
    ) {
        self.sessionStore = sessionStore
        self.zoomStore = zoomStore
        self.recentDocumentsStore = recentDocumentsStore
        self.hiddenFilesPreference = hiddenFilesPreference
    }

    /// 不可視ファイル表示のON/OFFを反転し、開いている全ウィンドウのサイドバーへ即座に反映する。
    func toggleHiddenFiles() {
        hiddenFilesPreference.showHiddenFiles.toggle()
        refreshAllSidebars()
    }

    /// 開いている全ウィンドウのサイドバー(ファイル一覧)を再読み込みする。
    func refreshAllSidebars() {
        for controller in controllers.values {
            controller.sidebar.refreshFileList()
        }
    }
```

`BefoldApp/befold/App/ViewerWindowManager.swift:34-38` の `ViewerWindowController` 生成箇所を以下に置き換える。

```swift
        let controller = ViewerWindowController(
            fileURL: url,
            zoomStore: zoomStore,
            hiddenFilesPreference: hiddenFilesPreference,
            forceSidebarVisible: forceSidebarVisible
        )
```

`BefoldApp/befold/App/ViewerWindowManager.swift` の `bindCallbacks(for:key:url:)` 内(既存の `controller.onSwitchFile = ...` の直後、95〜103行目付近)に追加する。

```swift
        controller.onToggleHiddenFiles = { [weak self] in
            self?.toggleHiddenFiles()
        }
```

`BefoldApp/befold/App/ViewerWindowController.swift` の `onSwitchFile` プロパティ宣言(43-44行目)の直後にコールバックプロパティを追加する。

```swift
    /// switchFile(to:) でファイルを切り替えたときに旧 URL・新 URL を通知するコールバック。
    var onSwitchFile: ((_ old: URL, _ new: URL) -> Void)?
    /// サイドバーのアイコンボタンから不可視ファイル表示切替が要求されたときに呼ばれるコールバック。
    /// ViewerWindowManager が toggleHiddenFiles() を束ねるために使用する。
    var onToggleHiddenFiles: (() -> Void)?
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter ViewerWindowManagerTests`
Expected: PASS(新規3テストを含め全 `ViewerWindowManagerTests` が通る)

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/ViewerWindowManager.swift BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befoldTests/ViewerWindowManagerTests.swift
git commit -m "feat: ViewerWindowManager に不可視ファイル表示の一括切替を追加する"
```

---

### Task 6: `AppDelegate` にトグルアクションを追加する

**Files:**
- Modify: `BefoldApp/befold/App/AppDelegate.swift:7-35,107-`

**Interfaces:**
- Consumes: `HiddenFilesPreference`(Task 1)、`ViewerWindowManager.init(...hiddenFilesPreference:)` / `toggleHiddenFiles()`(Task 5)
- Produces: `@objc func AppDelegate.toggleHiddenFiles(_ sender: Any?)`、`AppDelegate: NSMenuItemValidation`

このタスクはアプリライフサイクル層で、既存の `showOpenPanel` / `checkForUpdates` などの `AppDelegate` アクション同様に自動テスト対象外(手動確認・GUI 層)とする。Task 7 で `MainMenuBuilder` 経由のメニュー項目自体は自動テストする。

- [ ] **Step 1: 実装を書く**

`BefoldApp/befold/App/AppDelegate.swift:7-9` のプロパティ群に追加する。

```swift
    private(set) static var shared: AppDelegate?
    private let sessionStore: SessionStore
    private let windowManager: ViewerWindowManager
    private let hiddenFilesPreference: HiddenFilesPreference
    private let sessionRestorer: SessionRestorer
```

`BefoldApp/befold/App/AppDelegate.swift:21-35` の `init()` を以下に置き換える。

```swift
    override init() {
        let sessionStore = SessionStore()
        let zoomStore = ZoomStore()
        let recentDocumentsStore = RecentDocumentsStore()
        let hiddenFilesPreference = HiddenFilesPreference()
        let windowManager = ViewerWindowManager(
            sessionStore: sessionStore,
            zoomStore: zoomStore,
            recentDocumentsStore: recentDocumentsStore,
            hiddenFilesPreference: hiddenFilesPreference
        )
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.windowManager = windowManager
        self.hiddenFilesPreference = hiddenFilesPreference
        sessionRestorer = SessionRestorer(sessionStore: sessionStore, windowManager: windowManager)
        super.init()
    }
```

`BefoldApp/befold/App/AppDelegate.swift` の `installCLI(_:)` アクション(168-178行目)の直後、末尾の `}` の前に追加する。

```swift
    /// View > Show/Hide Hidden Files(⌘.)。不可視ファイル表示を全ウィンドウで一括切替する。
    @objc func toggleHiddenFiles(_ sender: Any?) {
        windowManager.toggleHiddenFiles()
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHiddenFiles(_:)) {
            menuItem.title = hiddenFilesPreference.showHiddenFiles
                ? String(localized: "menu.view.hideHiddenFiles", bundle: .l10n)
                : String(localized: "menu.view.showHiddenFiles", bundle: .l10n)
        }
        return true
    }
}
```

(既存ファイル末尾の `}` を1つ手前へ移し、上記のとおり `AppDelegate` 本体を閉じた直後に `NSMenuItemValidation` 拡張を追加する形になる。)

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功

- [ ] **Step 3: コミット**

```bash
git add BefoldApp/befold/App/AppDelegate.swift
git commit -m "feat: AppDelegate に不可視ファイル表示トグルアクションを追加する"
```

---

### Task 7: View メニューに項目を追加する

**Files:**
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift:181-193`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`
- Test: `BefoldApp/befoldTests/MainMenuBuilderTests.swift`

**Interfaces:**
- Consumes: `AppDelegate.toggleHiddenFiles(_:)`(Task 6)
- Produces: View メニューの `Cmd+.` 項目(セレクタ `#selector(AppDelegate.toggleHiddenFiles(_:))`)

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/MainMenuBuilderTests.swift:72-88` の `menuItemHasKeyEquivalent` の `arguments` 配列に、`toggleLineNumbers` の行の直後へ以下のタプルを追加する。

```swift
        (
            submenuKey: "menu.view.title",
            selector: #selector(AppDelegate.toggleHiddenFiles(_:)),
            key: ".", modifiers: NSEvent.ModifierFlags?.some(.command)
        ), // View メニューに Show Hidden Files(⌘.) がある
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`
Expected: FAIL(View メニューに `#selector(AppDelegate.toggleHiddenFiles(_:))` を持つ項目が存在せず `#require` が失敗)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/App/MainMenuBuilder.swift:186-187` を以下に置き換える(`toggleSidebar` の修飾キー設定と、その次の区切り線の間に新規項目を挿入する)。

```swift
        toggleSidebar.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "menu.view.showHiddenFiles", bundle: .l10n),
            action: #selector(AppDelegate.toggleHiddenFiles(_:)),
            keyEquivalent: "."
        )
```

`BefoldApp/befold/Resources/Localizable.xcstrings` の `"menu.view.hideLineNumbers"` エントリ(214-220行目)の直後に、以下の2エントリを追加する。

```json
    "menu.view.showHiddenFiles" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Show Hidden Files" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "不可視ファイルを表示" } }
      }
    },
    "menu.view.hideHiddenFiles" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Hide Hidden Files" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "不可視ファイルを隠す" } }
      }
    },
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`
Expected: PASS(全 `MainMenuBuilderTests` が通る)

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/MainMenuBuilder.swift BefoldApp/befold/Resources/Localizable.xcstrings BefoldApp/befoldTests/MainMenuBuilderTests.swift
git commit -m "feat: View メニューに不可視ファイル表示切替(⌘.)を追加する"
```

---

### Task 8: サイドバーにアイコンボタンを追加する

**Files:**
- Modify: `BefoldApp/befold/Viewer/FileListView.swift:4-10,46-58`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`(`FileListView` 生成箇所)
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ViewerWindowController.onToggleHiddenFiles`(Task 5)、`FileListModel.showHiddenFiles`(Task 3)
- Produces: `FileListView.onToggleHiddenFiles: (() -> Void)?`(オプショナル、既存の `onNavigateHistory` と同型なので未指定でも既存呼び出し元・テストは変更不要)

このタスクは SwiftUI のボタン外観そのものであり、本プロジェクトの規約(WebView/GUI 層は自動テスト対象外)により自動テストは追加しない。実装後にリリース前手動チェックでアイコン・ツールチップ・複数ウィンドウ連動を確認する(Task 9)。

- [ ] **Step 1: 実装を書く**

`BefoldApp/befold/Viewer/FileListView.swift:4-10` のプロパティ群に追加する。

```swift
struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void
    let onNavigate: (URL) -> Void
    let onSortOrderChanged: (SortOrder) -> Void
    let onOpenInNewWindow: (URL) -> Void
    var onNavigateHistory: ((Int) -> Void)?
    var onToggleHiddenFiles: (() -> Void)?
```

`BefoldApp/befold/Viewer/FileListView.swift:46-57` の `header` 内、既存のソートボタンの直後に新規ボタンを追加する。

```swift
            Button {
                let next: SortOrder = model.sortOrder == .foldersFirst ? .alphabetical : .foldersFirst
                onSortOrderChanged(next)
            } label: {
                Image(systemName: model.sortOrder == .foldersFirst
                    ? "folder.fill" : "textformat.abc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(model.sortOrder == .foldersFirst
                ? String(localized: "sidebar.sort.alphabetical", bundle: .l10n)
                : String(localized: "sidebar.sort.foldersFirst", bundle: .l10n))

            Button {
                onToggleHiddenFiles?()
            } label: {
                Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
                    .foregroundStyle(model.showHiddenFiles ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(model.showHiddenFiles
                ? String(localized: "sidebar.hiddenFiles.hide", bundle: .l10n)
                : String(localized: "sidebar.hiddenFiles.show", bundle: .l10n))
```

`BefoldApp/befold/App/ViewerWindowController.swift` の `makeSplitViewController()` 内、`FileListView(...)` 生成箇所(149-162行目)を以下に置き換える。

```swift
        let fileListView = FileListView(
            model: fileListModel,
            onSelect: { [weak self] url in self?.switchFile(to: url) },
            onNavigate: { [weak self] url in self?.navigateToFolder(url) },
            onSortOrderChanged: { [weak self] order in
                guard let self else { return }
                fileListModel.sortOrder = order
                sidebar.refreshFileList()
            },
            onOpenInNewWindow: { url in
                AppDelegate.shared?.openViewer(for: url)
            },
            onNavigateHistory: { [weak self] offset in self?.navigateHistory(by: offset) },
            onToggleHiddenFiles: { [weak self] in self?.onToggleHiddenFiles?() }
        )
```

`BefoldApp/befold/Resources/Localizable.xcstrings` の `"sidebar.sort.foldersFirst"` エントリ(389-395行目)の直後に、以下の2エントリを追加する。

```json
    "sidebar.hiddenFiles.show" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Show Hidden Files" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "不可視ファイルを表示" } }
      }
    },
    "sidebar.hiddenFiles.hide" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Hide Hidden Files" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "不可視ファイルを隠す" } }
      }
    },
```

- [ ] **Step 2: ビルドとテストスイート全体を確認する**

Run: `cd BefoldApp && swift build && swift test`
Expected: ビルド成功、全テスト PASS(`FileListViewTests` の `makeView` は `onToggleHiddenFiles` を渡していないが省略可能なため変更不要)

- [ ] **Step 3: コミット**

```bash
git add BefoldApp/befold/Viewer/FileListView.swift BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befold/Resources/Localizable.xcstrings
git commit -m "feat: サイドバーに不可視ファイル表示切替アイコンボタンを追加する"
```

---

### Task 9: 手動確認

**Files:** なし(コード変更なし)

- [ ] **Step 1: アプリを起動する**

Run: `cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold`(または `/run` スキル)し、ドットファイルを含むフォルダーを開く。

- [ ] **Step 2: 3つの操作経路を確認する**

- `Cmd+.` でサイドバーのドットファイル・ドットフォルダーが表示/非表示になること
- View メニューの項目が「不可視ファイルを表示」⇔「不可視ファイルを隠す」に文言反転すること
- サイドバー右上のアイコンボタン(ソートボタンの隣)が `eye.slash` ⇔ `eye` に切り替わり、クリックでも同様に切り替わること

- [ ] **Step 3: 複数ウィンドウ連動を確認する**

2つ以上のウィンドウを開いた状態でいずれか1つの操作経路を実行し、他の全ウィンドウのサイドバー表示・アイコン・メニュー文言が即座に連動することを確認する。

- [ ] **Step 4: 永続化を確認する**

不可視ファイルを表示状態にしたままアプリを終了・再起動し、表示状態が引き継がれることを確認する。

- [ ] **Step 5: コミット**

このタスクはコード変更を伴わないため、コミット不要。手動確認完了をユーザーへ報告する。
