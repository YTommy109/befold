# セッションレイアウト復元（アクティブファイル + タブ順序）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 起動時に、終了時のタブグループ構成・タブ並び順・選択タブ・アクティブ（キー）ウィンドウを復元する。

**Architecture:** `SessionStore` に Codable な `SessionLayout`（タブグループ構成）と別キーのアクティブファイルパスを追加する。タブ構成は `applicationShouldTerminate` で `NSWindow.tabGroup` からスナップショット保存し、アクティブファイルは `windowDidBecomeKey` でライブ更新する。復元時はレイアウトどおり `addTabbedWindow` で明示的にタブ化し、最後にアクティブファイルを `makeKeyAndOrderFront` する。既存の「開いた順フラット配列」はフォールバックとして維持する。

**Tech Stack:** Swift 6 / AppKit（macOS 14+）、Swift Testing、UserDefaults 永続化

**Spec:** `docs/superpowers/specs/2026-07-03-session-layout-restore-design.md`

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）。`SessionStore` は `@MainActor`
- テスト関数名は英語 camelCase。日本語説明は `@Test("...")` の表示名で付ける
- コミットは Conventional Commits + 日本語
- ビルド・テストは `MmdviewApp/` ディレクトリで実行する: `cd MmdviewApp && swift test`（要 Xcode.app）
- UserDefaults キー: レイアウト = `"SessionLayout"`（JSON Data）、アクティブファイル = `"SessionActiveFilePath"`（String）、既存の開いた順リスト = `"SessionOpenFilePaths"`（[String]、変更しない）
- パスはすべて `url.normalizedPathKey`（`URL+PathKey.swift`、シンボリックリンク解決済み絶対パス）で正規化する
- **コミット粒度（ユーザー方針）**: この機能の実装コミットは 1 つにまとめる。Task 1 で新規コミットを作り、Task 2 以降は `git commit --amend --no-edit` で統合する（未 push が前提。`git log origin/feat/recovery..HEAD` で確認できる）

---

### Task 1: SessionLayout 型と保存/読込 API

**Files:**
- Modify: `MmdviewApp/mmdview/App/SessionStore.swift`
- Test: `MmdviewApp/mmdviewTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `URL.normalizedPathKey`（既存、`URL+PathKey.swift`）
- Produces:
  - `struct SessionLayout: Codable, Equatable { struct TabGroup: Codable, Equatable { var paths: [String]; var selectedPath: String? }; var groups: [TabGroup] }`（トップレベル型、`SessionStore.swift` 内に定義）
  - `SessionStore.saveLayout(_ layout: SessionLayout)`
  - `SessionStore.savedLayout() -> SessionLayout?`（未保存・パース不能・groups 空なら nil）

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/SessionStoreTests.swift` の `SessionStoreTests` struct 内に追加:

```swift
    @Test
    func savedLayoutIsNilInitially() {
        let store = SessionStore(defaults: makeDefaults())

        #expect(store.savedLayout() == nil)
    }

    @Test
    func saveLayoutRoundTripsAcrossInstances() {
        let defaults = makeDefaults()
        let layout = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: ["/tmp/a.mmd", "/tmp/b.md"], selectedPath: "/tmp/b.md"),
            SessionLayout.TabGroup(paths: ["/tmp/c.mmd"], selectedPath: "/tmp/c.mmd"),
        ])

        SessionStore(defaults: defaults).saveLayout(layout)

        #expect(SessionStore(defaults: defaults).savedLayout() == layout)
    }

    @Test("壊れた JSON は nil を返しフォールバックに切り替わる")
    func savedLayoutReturnsNilForCorruptData() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "SessionLayout")

        #expect(SessionStore(defaults: defaults).savedLayout() == nil)
    }

    @Test("空のレイアウトは nil 扱いでフォールバックに切り替わる")
    func savedLayoutReturnsNilForEmptyGroups() {
        let defaults = makeDefaults()
        SessionStore(defaults: defaults).saveLayout(SessionLayout(groups: []))

        #expect(SessionStore(defaults: defaults).savedLayout() == nil)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter SessionStoreTests`
Expected: コンパイルエラー `cannot find 'SessionLayout' in scope`（Swift ではシンボル未定義はコンパイル失敗として現れる。これが TDD の「失敗」に相当する）

- [ ] **Step 3: 最小実装を書く**

`MmdviewApp/mmdview/App/SessionStore.swift` の `import Foundation` の直後（`SessionStore` クラス定義の前）に追加:

```swift
/// 終了時のウィンドウ/タブ構成。groups はウィンドウ(タブグループ)の前面からの並び、
/// 各グループの paths はタブの並び順(正規化パス)。
struct SessionLayout: Codable, Equatable {
    struct TabGroup: Codable, Equatable {
        /// タブの並び順(normalizedPathKey)
        var paths: [String]
        /// このグループで選択されていたタブ
        var selectedPath: String?
    }

    /// ウィンドウ(タブグループ)の並び
    var groups: [TabGroup]
}
```

`SessionStore` クラス内、`private static let defaultsKey = "SessionOpenFilePaths"` の下にキーを追加:

```swift
    private static let layoutKey = "SessionLayout"
```

`freeze()` メソッドの下にメソッドを追加:

```swift
    /// 終了時のウィンドウ/タブ構成を保存する。
    func saveLayout(_ layout: SessionLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Self.layoutKey)
    }

    /// 保存済みのウィンドウ/タブ構成を返す。未保存・パース不能・空の場合は nil(フォールバック用)。
    func savedLayout() -> SessionLayout? {
        guard let data = defaults.data(forKey: Self.layoutKey),
              let layout = try? JSONDecoder().decode(SessionLayout.self, from: data),
              !layout.groups.isEmpty
        else { return nil }
        return layout
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter SessionStoreTests`
Expected: PASS（既存 5 件 + 新規 4 件）

- [ ] **Step 5: コミット（この機能の起点コミットを新規作成）**

```bash
git add MmdviewApp/mmdview/App/SessionStore.swift MmdviewApp/mmdviewTests/SessionStoreTests.swift
git commit -m "feat: 起動時にアクティブファイルとタブ構成を復元する

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: SessionLayout.filtered(to:) — 復元前の絞り込みロジック

**Files:**
- Modify: `MmdviewApp/mmdview/App/SessionStore.swift`（`SessionLayout` にメソッド追加）
- Create: `MmdviewApp/mmdviewTests/SessionLayoutTests.swift`

**Interfaces:**
- Consumes: Task 1 の `SessionLayout` / `SessionLayout.TabGroup`
- Produces: `SessionLayout.filtered(to availablePaths: Set<String>) -> SessionLayout` — 存在するパスだけに絞り、空グループを除去し、消えた選択タブはグループ先頭で代替する

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/SessionLayoutTests.swift` を新規作成:

```swift
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
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter SessionLayoutTests`
Expected: コンパイルエラー `value of type 'SessionLayout' has no member 'filtered'`

- [ ] **Step 3: 最小実装を書く**

`MmdviewApp/mmdview/App/SessionStore.swift` の `SessionLayout` struct 内、`var groups: [TabGroup]` の下に追加:

```swift
    /// 存在するパスだけに絞り込む。空になったグループは取り除き、
    /// 選択タブが消えた場合はグループ先頭で代替する。
    func filtered(to availablePaths: Set<String>) -> SessionLayout {
        var filteredGroups: [TabGroup] = []
        for group in groups {
            let paths = group.paths.filter { availablePaths.contains($0) }
            guard !paths.isEmpty else { continue }
            let selectedPath = group.selectedPath.flatMap { paths.contains($0) ? $0 : nil } ?? paths.first
            filteredGroups.append(TabGroup(paths: paths, selectedPath: selectedPath))
        }
        return SessionLayout(groups: filteredGroups)
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter SessionLayoutTests`
Expected: PASS（3 件）

- [ ] **Step 5: amend コミット**

```bash
git add MmdviewApp/mmdview/App/SessionStore.swift MmdviewApp/mmdviewTests/SessionLayoutTests.swift
git commit --amend --no-edit
```

---

### Task 3: アクティブファイルの記録

**Files:**
- Modify: `MmdviewApp/mmdview/App/SessionStore.swift`
- Test: `MmdviewApp/mmdviewTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: Task 1 のキー定義パターン、`URL.normalizedPathKey`
- Produces:
  - `SessionStore.noteActivated(_ url: URL)` — `"SessionActiveFilePath"` に正規化パスを保存
  - `SessionStore.savedActivePath() -> String?`
  - `noteClosed(_:)` の拡張: 閉じたファイルがアクティブ記録と一致したら記録をクリア（freeze 中は従来どおり何もしない）

- [ ] **Step 1: 失敗するテストを書く**

`SessionStoreTests` struct 内に追加:

```swift
    @Test
    func noteActivatedPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/active.mmd")

        SessionStore(defaults: defaults).noteActivated(url)

        #expect(SessionStore(defaults: defaults).savedActivePath() == url.normalizedPathKey)
    }

    @Test("アクティブファイルを閉じたら記録もクリアされる")
    func noteClosedClearsMatchingActivePath() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/active.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(url)
        store.noteActivated(url)

        store.noteClosed(url)

        #expect(store.savedActivePath() == nil)
    }

    @Test("別ファイルを閉じてもアクティブ記録は残る")
    func noteClosedKeepsUnrelatedActivePath() {
        let defaults = makeDefaults()
        let active = URL(fileURLWithPath: "/tmp/active.mmd")
        let other = URL(fileURLWithPath: "/tmp/other.md")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(active)
        store.noteOpened(other)
        store.noteActivated(active)

        store.noteClosed(other)

        #expect(store.savedActivePath() == active.normalizedPathKey)
    }

    @Test("freeze 後の noteClosed はアクティブ記録もクリアしない")
    func noteClosedAfterFreezeKeepsActivePath() {
        let defaults = makeDefaults()
        let url = URL(fileURLWithPath: "/tmp/active.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteOpened(url)
        store.noteActivated(url)

        store.freeze()
        store.noteClosed(url)

        #expect(store.savedActivePath() == url.normalizedPathKey)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter SessionStoreTests`
Expected: コンパイルエラー `value of type 'SessionStore' has no member 'noteActivated'`

- [ ] **Step 3: 最小実装を書く**

`SessionStore` クラス内、`private static let layoutKey = "SessionLayout"` の下にキーを追加:

```swift
    private static let activeKey = "SessionActiveFilePath"
```

`savedLayout()` の下にメソッドを追加:

```swift
    /// アクティブ(キーウィンドウ)になったファイルを記録する。
    func noteActivated(_ url: URL) {
        defaults.set(url.normalizedPathKey, forKey: Self.activeKey)
    }

    /// 前回アクティブだったファイルの正規化パスを返す。
    func savedActivePath() -> String? {
        defaults.string(forKey: Self.activeKey)
    }
```

`noteClosed(_:)` を次のとおり変更（末尾にアクティブ記録のクリアを追加）:

```swift
    /// ファイルが閉じられたことを記録する。freeze 後は無視する。
    /// 閉じたファイルがアクティブ記録と一致する場合は記録もクリアする。
    func noteClosed(_ url: URL) {
        guard !isFrozen else { return }
        let path = url.normalizedPathKey
        let paths = savedPaths().filter { $0 != path }
        defaults.set(paths, forKey: Self.defaultsKey)
        if savedActivePath() == path {
            defaults.removeObject(forKey: Self.activeKey)
        }
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter SessionStoreTests`
Expected: PASS（既存 9 件 + 新規 4 件）

- [ ] **Step 5: amend コミット**

```bash
git add MmdviewApp/mmdview/App/SessionStore.swift MmdviewApp/mmdviewTests/SessionStoreTests.swift
git commit --amend --no-edit
```

---

### Task 4: リネーム追従 noteRenamed

**Files:**
- Modify: `MmdviewApp/mmdview/App/SessionStore.swift`
- Test: `MmdviewApp/mmdviewTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: Task 1 の `saveLayout` / `savedLayout`、Task 3 の `savedActivePath` / `activeKey`
- Produces: `SessionStore.noteRenamed(from oldURL: URL, to newURL: URL)` — アクティブ記録と保存済みレイアウト内の旧パスを新パスへ書き換える。開いた順リストの付け替えは従来どおり呼び出し側の `noteClosed` / `noteOpened` が担う（このメソッドでは触らない）

- [ ] **Step 1: 失敗するテストを書く**

`SessionStoreTests` struct 内に追加:

```swift
    @Test("rename でアクティブ記録が新パスに移る")
    func noteRenamedMigratesActivePath() {
        let defaults = makeDefaults()
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteActivated(old)

        store.noteRenamed(from: old, to: new)

        #expect(store.savedActivePath() == new.normalizedPathKey)
    }

    @Test("無関係なアクティブ記録は rename で変わらない")
    func noteRenamedKeepsUnrelatedActivePath() {
        let defaults = makeDefaults()
        let active = URL(fileURLWithPath: "/tmp/active.mmd")
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let store = SessionStore(defaults: defaults)
        store.noteActivated(active)

        store.noteRenamed(from: old, to: new)

        #expect(store.savedActivePath() == active.normalizedPathKey)
    }

    @Test("rename で保存済みレイアウト内のパスと選択タブが書き換わる")
    func noteRenamedRewritesLayoutPaths() {
        let defaults = makeDefaults()
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        let other = "/tmp/other.md"
        let store = SessionStore(defaults: defaults)
        store.saveLayout(SessionLayout(groups: [
            SessionLayout.TabGroup(paths: [other, old.normalizedPathKey], selectedPath: old.normalizedPathKey),
        ]))

        store.noteRenamed(from: old, to: new)

        let expected = SessionLayout(groups: [
            SessionLayout.TabGroup(paths: [other, new.normalizedPathKey], selectedPath: new.normalizedPathKey),
        ])
        #expect(store.savedLayout() == expected)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter SessionStoreTests`
Expected: コンパイルエラー `value of type 'SessionStore' has no member 'noteRenamed'`

- [ ] **Step 3: 最小実装を書く**

`SessionStore` クラス内、`savedActivePath()` の下に追加:

```swift
    /// rename / move をセッション記録に反映する。
    /// アクティブ記録と保存済みレイアウト内の旧パスを新パスへ書き換える。
    /// 開いているファイル一覧の付け替えは従来どおり noteClosed / noteOpened で行う。
    func noteRenamed(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.normalizedPathKey
        let newPath = newURL.normalizedPathKey
        guard oldPath != newPath else { return }

        if savedActivePath() == oldPath {
            defaults.set(newPath, forKey: Self.activeKey)
        }
        guard var layout = savedLayout() else { return }
        for index in layout.groups.indices {
            layout.groups[index].paths = layout.groups[index].paths.map { $0 == oldPath ? newPath : $0 }
            if layout.groups[index].selectedPath == oldPath {
                layout.groups[index].selectedPath = newPath
            }
        }
        saveLayout(layout)
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter SessionStoreTests`
Expected: PASS（既存 13 件 + 新規 3 件）

- [ ] **Step 5: amend コミット**

```bash
git add MmdviewApp/mmdview/App/SessionStore.swift MmdviewApp/mmdviewTests/SessionStoreTests.swift
git commit --amend --no-edit
```

---

### Task 5: ViewerWindowController に onBecomeKey コールバックを追加

**Files:**
- Modify: `MmdviewApp/mmdview/App/ViewerWindowController.swift`
- Test: `MmdviewApp/mmdviewTests/ViewerWindowControllerTests.swift`

**Interfaces:**
- Consumes: なし（既存の NSWindowDelegate 実装に追加するだけ）
- Produces: `ViewerWindowController.onBecomeKey: (() -> Void)?` と `windowDidBecomeKey(_:)` 実装。Task 6 の AppDelegate がこのコールバックに `sessionStore.noteActivated(controller.fileURL)` を配線する

- [ ] **Step 1: 失敗するテストを書く**

`MmdviewApp/mmdviewTests/ViewerWindowControllerTests.swift` の `ViewerWindowControllerTests` struct 内に追加（既存の `makeTempFile` / `makeDefaults` ヘルパーを使う）:

```swift
    @Test("windowDidBecomeKey で onBecomeKey コールバックが呼ばれる")
    func windowDidBecomeKeyInvokesCallback() throws {
        let (dir, file) = try makeTempFile(named: "diagram.mmd")
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = ViewerWindowController(fileURL: file, zoomStore: ZoomStore(defaults: makeDefaults()))
        defer { controller.close() }
        var becameKey = false
        controller.onBecomeKey = { becameKey = true }

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        #expect(becameKey)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerWindowControllerTests`
Expected: コンパイルエラー `value of type 'ViewerWindowController' has no member 'onBecomeKey'`

- [ ] **Step 3: 最小実装を書く**

`MmdviewApp/mmdview/App/ViewerWindowController.swift` の `var onRename: ...` 宣言の下にプロパティを追加:

```swift
    /// ウィンドウがキーウィンドウになったときに呼ばれるコールバック。
    /// AppDelegate がアクティブファイルのセッション記録の更新に使用する。
    var onBecomeKey: (() -> Void)?
```

`// MARK: - NSWindowDelegate` セクションの `windowWillClose(_:)` の下にデリゲートメソッドを追加:

```swift
    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey?()
    }
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerWindowControllerTests`
Expected: PASS（既存 2 件 + 新規 1 件）

- [ ] **Step 5: amend コミット**

```bash
git add MmdviewApp/mmdview/App/ViewerWindowController.swift MmdviewApp/mmdviewTests/ViewerWindowControllerTests.swift
git commit --amend --no-edit
```

---

### Task 6: AppDelegate 配線 — スナップショット保存・レイアウト復元・アクティブ追跡

**Files:**
- Modify: `MmdviewApp/mmdview/App/AppDelegate.swift`

**Interfaces:**
- Consumes:
  - `SessionStore.saveLayout(_:)` / `savedLayout()`（Task 1）
  - `SessionLayout.filtered(to:)`（Task 2）
  - `SessionStore.noteActivated(_:)` / `savedActivePath()`（Task 3）
  - `SessionStore.noteRenamed(from:to:)`（Task 4）
  - `ViewerWindowController.onBecomeKey`（Task 5）
- Produces: なし（最終配線。GUI 層のため自動テスト対象外 — プロジェクトのテスト規約どおり手動チェックで検証する）

- [ ] **Step 1: 復元用プロパティを追加する**

`AppDelegate` の `private var urlsToRestore: [URL] = []` の下に追加:

```swift
    /// 前回終了時のタブ構成。urlsToRestore と同様に applicationWillFinishLaunching で先読みする。
    private var layoutToRestore: SessionLayout?
    /// 前回アクティブだったファイルの正規化パス。
    private var activePathToRestore: String?
```

`applicationWillFinishLaunching(_:)` を次のとおり変更:

```swift
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = DocumentController()
        urlsToRestore = sessionStore.savedURLs()
        layoutToRestore = sessionStore.savedLayout()
        activePathToRestore = sessionStore.savedActivePath()
    }
```

- [ ] **Step 2: 終了時スナップショット保存を実装する**

`applicationShouldTerminate(_:)` を次のとおり変更:

```swift
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // ウィンドウが閉じられる前に、現在のタブ構成とアクティブファイルを確定値で保存する
        if let keyWindow = NSApp.keyWindow,
           let controller = keyWindow.windowController as? ViewerWindowController {
            sessionStore.noteActivated(controller.fileURL)
        }
        sessionStore.saveLayout(currentSessionLayout())
        // 終了処理中のウィンドウクローズで復元リストが空にならないよう記録を止める
        sessionStore.freeze()
        return .terminateNow
    }
```

`// MARK: - Window Management` セクションに 2 メソッドを追加:

```swift
    /// 現在のウィンドウ/タブ構成をスナップショットする。
    /// NSApp.orderedWindows は前面から順に返るため、グループの並びも前面優先で保存される。
    private func currentSessionLayout() -> SessionLayout {
        var groups: [SessionLayout.TabGroup] = []
        var seenWindows: Set<ObjectIdentifier> = []

        for window in NSApp.orderedWindows {
            guard !seenWindows.contains(ObjectIdentifier(window)),
                  viewerPath(of: window) != nil else { continue }

            let tabWindows = window.tabGroup?.windows ?? [window]
            for tabWindow in tabWindows {
                seenWindows.insert(ObjectIdentifier(tabWindow))
            }

            let paths = tabWindows.compactMap { viewerPath(of: $0) }
            guard !paths.isEmpty else { continue }
            let selectedWindow = window.tabGroup?.selectedWindow ?? window
            groups.append(SessionLayout.TabGroup(paths: paths, selectedPath: viewerPath(of: selectedWindow)))
        }
        return SessionLayout(groups: groups)
    }

    /// ビューアウィンドウなら対応するファイルの正規化パスを返す。
    private func viewerPath(of window: NSWindow) -> String? {
        (window.windowController as? ViewerWindowController)?.fileURL.normalizedPathKey
    }
```

- [ ] **Step 3: 復元処理をレイアウト対応にする**

`restoreLastSession()` を次のとおり全面的に置き換える:

```swift
    /// 前回セッションで開いていたファイルを再オープンする。存在しなくなったファイルは記録からも取り除く。
    /// SessionLayout があればタブグループ構成・タブ順・選択タブを再現し、無ければ従来どおり開いた順に開く。
    /// 最後に前回アクティブだったファイルをキーウィンドウにする。
    private func restoreLastSession() {
        let existingURLs = urlsToRestore.filter { url in
            if FileManager.default.fileExists(atPath: url.path) { return true }
            sessionStore.noteClosed(url)
            return false
        }
        urlsToRestore = []

        let urlByPath = Dictionary(existingURLs.map { ($0.normalizedPathKey, $0) }) { first, _ in first }
        var restoredPaths: Set<String> = []

        if let layout = layoutToRestore?.filtered(to: Set(urlByPath.keys)) {
            for group in layout.groups {
                restoreTabGroup(group, urlByPath: urlByPath)
                restoredPaths.formUnion(group.paths)
            }
        }
        layoutToRestore = nil

        // レイアウトに無いファイル(クラッシュ後に開いたもの等)は従来どおり開いた順に開く
        for url in existingURLs where !restoredPaths.contains(url.normalizedPathKey) {
            openViewer(for: url)
        }

        // 前回アクティブだったファイルをキーウィンドウにする(開けていなければ成り行きのまま)
        if let activePath = activePathToRestore,
           let window = windowControllers[activePath]?.window {
            window.makeKeyAndOrderFront(nil)
        }
        activePathToRestore = nil
    }

    /// 1 つのタブグループを復元する。先頭のウィンドウに残りを順にタブ連結し、選択タブを再現する。
    private func restoreTabGroup(_ group: SessionLayout.TabGroup, urlByPath: [String: URL]) {
        var previousWindow: NSWindow?
        for path in group.paths {
            guard let url = urlByPath[path] else { continue }
            openViewer(for: url)
            guard let window = windowControllers[path]?.window else { continue }
            // システムの「書類を開くときはタブで開く」設定に依存しないよう明示的にタブ化する
            previousWindow?.addTabbedWindow(window, ordered: .above)
            previousWindow = window
        }
        if let selectedPath = group.selectedPath,
           let selectedWindow = windowControllers[selectedPath]?.window {
            selectedWindow.tabGroup?.selectedWindow = selectedWindow
        }
    }
```

- [ ] **Step 4: onBecomeKey と noteRenamed を配線する**

`bindCallbacks(for:key:url:)` 内、`controller.onClose = ...` の前に追加:

```swift
        controller.onBecomeKey = { [weak self, weak controller] in
            guard let self, let controller else { return }
            // fileURL は rename で書き換わるため、クロージャ引数の url ではなく現在値を参照する
            sessionStore.noteActivated(controller.fileURL)
        }
```

`controller.onRename` クロージャ内、`sessionStore.noteClosed(oldURL)` の**前**に追加（noteClosed が旧パスのアクティブ記録をクリアする前に付け替える必要がある）:

```swift
            sessionStore.noteRenamed(from: oldURL, to: newURL)
```

- [ ] **Step 5: ビルドと全テストを実行する**

Run: `cd MmdviewApp && swift build && swift test`
Expected: ビルド成功、全テスト PASS（SessionStoreTests 16 件 / SessionLayoutTests 3 件 / ViewerWindowControllerTests 3 件 + その他既存テスト）

- [ ] **Step 6: amend コミット**

```bash
git add MmdviewApp/mmdview/App/AppDelegate.swift
git commit --amend --no-edit
```

---

### Task 7: 手動確認（GUI 層の受け入れテスト）

**Files:** なし（検証のみ）

**Interfaces:**
- Consumes: Task 1〜6 のすべて

- [ ] **Step 1: アプリをビルドして起動する**

`/run` スキル（または `cd MmdviewApp && swift build` 後に生成物を起動）でアプリを立ち上げ、`.mmd` / `.md` ファイルを 4 つ以上開く。

- [ ] **Step 2: シナリオ検証**

以下を順に確認する:

1. **タブ並び順**: 4 ファイルを 1 ウィンドウのタブにまとめ（Window > Merge All Windows）、タブをドラッグで並べ替える → アプリを Cmd+Q で終了 → 再起動 → **並べ替え後の順序**でタブが復元される
2. **選択タブ + アクティブ**: 2 番目のタブを選択した状態で終了 → 再起動 → 2 番目のタブが選択済みでウィンドウがキーになっている
3. **複数グループ**: タブを 1 枚ドラッグで分離して 2 ウィンドウ構成にする → 片方をアクティブにして終了 → 再起動 → 2 ウィンドウ構成・各グループのタブ構成・アクティブウィンドウが再現される
4. **ファイル消失**: 開いていたファイルを 1 つ Finder で削除して起動 → 該当タブだけスキップされ、残りは正しく復元される
5. **旧データからの移行**: `defaults delete <bundle-id> SessionLayout` でレイアウトだけ消して起動 → フラット配列フォールバックで全ファイルが開く（従来挙動）

- [ ] **Step 3: 問題があれば修正して amend、なければ完了報告**

問題が見つかった場合は修正して `git commit --amend --no-edit` で統合し、Step 1 から再確認する。
