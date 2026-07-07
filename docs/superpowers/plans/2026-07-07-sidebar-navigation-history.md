# サイドバー ナビゲーション履歴（戻る/進む）実装計画

<!-- constrained-by ../specs/2026-07-07-sidebar-navigation-history-design.md -->

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サイドバー上部に「戻る/進む」ボタンを追加し、ディレクトリ移動とファイル参照を1本の履歴として辿れるようにする（Safari 風の長押し/右クリック履歴メニュー付き）。

**Architecture:** 純ロジックの `NavigationHistory`（戻る/進むスタック）を新設し、`ViewerWindowController` がタブごとに1つ保持する。`switchFile`/`navigateToFolder` の末尾でユーザー操作時にスナップショットを push、戻る/進む適用時は `isApplyingHistory` ガードで再 push を抑止する。サイドバーへは `FileListModel` 経由で履歴状態を渡し、`FileListView.header` の `Menu`（primaryAction=移動 / hold=履歴メニュー）で操作する。

**Tech Stack:** Swift 6（strict concurrency）/ AppKit（NSWindowController）+ SwiftUI / Swift Testing。

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）。`NavigationHistory` は `@MainActor` にする（`ViewerWindowController` は NSWindowController なので暗黙 `@MainActor`）。
- URL の同一判定・置換は既存の `url.normalizedPathKey`（`BefoldApp/befold/App/URL+PathKey.swift`、`resolvingSymlinksInPath().path`）で行う。
- テスト関数名は英語 camelCase。日本語説明は `@Test("…")` の表示名で付ける（SwiftLint `identifier_name` 対策）。
- 追加するローカライズキーは **en / ja 両方** を `Localizable.xcstrings` に入れる（`LocalizationTests.allKeysHaveBothLanguages` が全キーの両言語訳を必須化している）。
- 履歴は永続化しない（メモリ内・タブ生存中のみ）。
- 新規 `.swift` ファイルは `befold/` 配下に置けば XcodeGen / SPM のディレクトリグロブで自動的に取り込まれる（マニフェスト編集不要。ただし `.xcodeproj` 利用者向けに最後に `xcodegen generate` を回す）。
- コマンドは `cd BefoldApp` してから実行する（`swift test` は Xcode.app 必須）。

## File Structure

- **Create** `BefoldApp/befold/App/NavigationHistory.swift` — `HistoryEntry`（値型スナップショット）と `NavigationHistory`（戻る/進むスタック、純ロジック）。
- **Create** `BefoldApp/befoldTests/NavigationHistoryTests.swift` — `NavigationHistory` の網羅的単体テスト。
- **Modify** `BefoldApp/befold/App/ViewerWindowController.swift` — 履歴の保持・記録・適用・rename 連携。
- **Modify** `BefoldApp/befoldTests/ViewerWindowControllerTests.swift` — 履歴記録・戻る/進む・ガードの `@MainActor` テストを追加。
- **Modify** `BefoldApp/befold/Viewer/FileListView.swift` — `FileListModel` に履歴プロパティ追加、`FileListView` に戻る/進む `Menu` とコールバック追加。
- **Modify** `BefoldApp/befold/Resources/Localizable.xcstrings` — `sidebar.nav.back` / `sidebar.nav.forward` を追加。

---

### Task 1: `NavigationHistory`（純ロジック）

**Files:**
- Create: `BefoldApp/befold/App/NavigationHistory.swift`
- Test: `BefoldApp/befoldTests/NavigationHistoryTests.swift`

**Interfaces:**
- Produces:
  - `struct HistoryEntry: Equatable { let directory: URL; let file: URL? }`（`==` は directory/file の `normalizedPathKey` で比較）
  - `@MainActor final class NavigationHistory` with:
    - `private(set) var entries: [HistoryEntry]`
    - `private(set) var currentIndex: Int`（空のとき `-1`）
    - `var canGoBack: Bool` / `var canGoForward: Bool`
    - `func push(_ entry: HistoryEntry)`
    - `func move(by offset: Int) -> HistoryEntry?`
    - `func backEntries() -> [HistoryEntry]`（新しい順）
    - `func forwardEntries() -> [HistoryEntry]`（近い順）
    - `func renameOccurred(from oldURL: URL, to newURL: URL)`

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/NavigationHistoryTests.swift` を新規作成:

```swift
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct NavigationHistoryTests {
    private let dir = URL(fileURLWithPath: "/files")
    private func entry(_ name: String) -> HistoryEntry {
        HistoryEntry(directory: dir, file: dir.appendingPathComponent(name))
    }

    @Test("push で履歴が積まれ現在地が末尾になる")
    func pushAppendsAndAdvances() {
        let history = NavigationHistory()
        #expect(history.canGoBack == false)

        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))

        #expect(history.entries.count == 2)
        #expect(history.currentIndex == 1)
        #expect(history.canGoBack == true)
        #expect(history.canGoForward == false)
    }

    @Test("同一スナップショットの連続 push は無視される")
    func duplicatePushIsIgnored() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("a.mmd"))

        #expect(history.entries.count == 1)
        #expect(history.currentIndex == 0)
    }

    @Test("move(by:) で戻り currentIndex とエントリが変わる")
    func moveBackReturnsEntry() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))

        let moved = history.move(by: -1)

        #expect(moved == entry("a.mmd"))
        #expect(history.currentIndex == 0)
        #expect(history.canGoForward == true)
    }

    @Test("範囲外の move は nil を返し現在地を変えない")
    func moveOutOfBoundsReturnsNil() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))

        #expect(history.move(by: -1) == nil)
        #expect(history.currentIndex == 0)
        #expect(history.move(by: 5) == nil)
        #expect(history.currentIndex == 0)
    }

    @Test("戻った後の新規 push で進む履歴が破棄される")
    func pushTruncatesForwardHistory() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))
        history.push(entry("c.mmd"))
        _ = history.move(by: -2) // -> a

        history.push(entry("d.mmd"))

        #expect(history.entries.map(\.file?.lastPathComponent) == ["a.mmd", "d.mmd"])
        #expect(history.currentIndex == 1)
        #expect(history.canGoForward == false)
    }

    @Test("backEntries は新しい順、forwardEntries は近い順")
    func backAndForwardEntriesOrdering() {
        let history = NavigationHistory()
        history.push(entry("a.mmd"))
        history.push(entry("b.mmd"))
        history.push(entry("c.mmd"))
        _ = history.move(by: -1) // 現在 b（a<-b->c）

        #expect(history.backEntries().map(\.file?.lastPathComponent) == ["a.mmd"])
        #expect(history.forwardEntries().map(\.file?.lastPathComponent) == ["c.mmd"])
    }

    @Test("renameOccurred で履歴内の該当ファイルが差し替わる")
    func renameRemapsMatchingEntries() {
        let history = NavigationHistory()
        history.push(entry("old.mmd"))
        history.push(entry("b.mmd"))
        let new = dir.appendingPathComponent("new.mmd")

        history.renameOccurred(from: dir.appendingPathComponent("old.mmd"), to: new)

        #expect(history.entries[0].file?.lastPathComponent == "new.mmd")
        #expect(history.entries[1].file?.lastPathComponent == "b.mmd")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter NavigationHistoryTests`
Expected: FAIL（`cannot find 'NavigationHistory' in scope` などのコンパイルエラー）

- [ ] **Step 3: 実装を書く**

`BefoldApp/befold/App/NavigationHistory.swift` を新規作成:

```swift
import Foundation

/// 戻る/進む履歴の 1 エントリ。表示ディレクトリと表示ファイルのスナップショット。
struct HistoryEntry: Equatable {
    let directory: URL
    let file: URL?

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.directory.normalizedPathKey == rhs.directory.normalizedPathKey
            && lhs.file?.normalizedPathKey == rhs.file?.normalizedPathKey
    }
}

/// タブ 1 つ分の戻る/進むナビゲーション履歴。統合 1 本のスタックとして
/// ディレクトリ移動とファイル参照を時系列で保持する。永続化はしない。
@MainActor
final class NavigationHistory {
    private(set) var entries: [HistoryEntry] = []
    /// 現在地。空のときは -1。
    private(set) var currentIndex: Int = -1

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex >= 0 && currentIndex < entries.count - 1 }

    /// 現在エントリと同一なら何もしない（重複防止）。
    /// そうでなければ「進む」履歴を破棄して末尾に追加し、現在地を末尾へ進める。
    func push(_ entry: HistoryEntry) {
        if currentIndex >= 0, entries[currentIndex] == entry { return }
        if currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)...)
        }
        entries.append(entry)
        currentIndex = entries.count - 1
    }

    /// 現在地を offset だけ移動して移動先エントリを返す。範囲外なら nil（現在地不変）。
    func move(by offset: Int) -> HistoryEntry? {
        let target = currentIndex + offset
        guard entries.indices.contains(target) else { return nil }
        currentIndex = target
        return entries[target]
    }

    /// 戻るメニュー用。現在地の 1 つ前から先頭に向かって新しい順。
    func backEntries() -> [HistoryEntry] {
        guard currentIndex > 0 else { return [] }
        return (0..<currentIndex).reversed().map { entries[$0] }
    }

    /// 進むメニュー用。現在地の 1 つ後から末尾に向かって近い順。
    func forwardEntries() -> [HistoryEntry] {
        guard currentIndex >= 0, currentIndex < entries.count - 1 else { return [] }
        return ((currentIndex + 1)..<entries.count).map { entries[$0] }
    }

    /// rename/move 時に履歴内の該当ファイル参照を新 URL へ差し替える（陳腐化防止）。
    func renameOccurred(from oldURL: URL, to newURL: URL) {
        let oldKey = oldURL.normalizedPathKey
        entries = entries.map { entry in
            guard let file = entry.file, file.normalizedPathKey == oldKey else { return entry }
            return HistoryEntry(directory: entry.directory, file: newURL)
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter NavigationHistoryTests`
Expected: PASS（7 tests）

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/App/NavigationHistory.swift befoldTests/NavigationHistoryTests.swift
git commit -m "feat: 戻る/進み履歴の NavigationHistory を追加する"
```

---

### Task 2: `ViewerWindowController` への履歴組み込み

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`
- Test: `BefoldApp/befoldTests/ViewerWindowControllerTests.swift`

**Interfaces:**
- Consumes: Task 1 の `NavigationHistory` / `HistoryEntry`、`FileListModel`（Task 3 で履歴プロパティ追加。本タスクでは `refreshHistoryState()` 内で `canGoBack`/`canGoForward`/`backHistory`/`forwardHistory` に代入するので、**Task 3 の `FileListModel` 変更を先に入れておく必要がある**。実装順は Task 3 の Step「FileListModel にプロパティ追加」を本タスク着手前に完了しておくこと。下記 Step 0 参照）。
- Produces:
  - `func navigateHistory(by offset: Int)`（サイドバーの戻る/進む・履歴メニューから呼ぶ）
  - `private func recordHistory()` / `private func applyHistoryEntry(_:)` / `private func refreshHistoryState()`
  - `private var isApplyingHistory: Bool`
  - `let history: NavigationHistory`

- [ ] **Step 0: 依存する FileListModel プロパティを先に追加**

`BefoldApp/befold/Viewer/FileListView.swift` の `FileListModel` に以下を追記する（`sortOrder` プロパティの直後、8-20 行目付近）:

```swift
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var backHistory: [HistoryEntry] = []
    var forwardHistory: [HistoryEntry] = []
```

（既存イニシャライザは変更不要。デフォルト値付きなので `FileListModel(currentDirectory:entries:selection:)` はそのまま動く。）

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/ViewerWindowControllerTests.swift` の末尾（最後の `}` の直前、`extension ViewerWindowControllerTests` にせずスイート内メソッドとして）に追加:

```swift
    @Test("初期状態では戻る履歴がない")
    func historyStartsEmpty() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "History"))
        )
        defer { controller.close() }

        #expect(controller.fileListModel.canGoBack == false)
        #expect(controller.fileListModel.canGoForward == false)
    }

    @Test("switchFile で履歴が積まれ戻ると元ファイルに復帰する")
    func switchFilePushesHistoryAndBackRestores() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "b.mmd", contents: "graph LR;")
        let fileB = fileA.deletingLastPathComponent().appendingPathComponent("b.mmd")
        let controller = ViewerWindowController(
            fileURL: fileA,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "History"))
        )
        defer { controller.close() }

        controller.switchFile(to: fileB)
        #expect(controller.fileURL.lastPathComponent == "b.mmd")
        #expect(controller.fileListModel.canGoBack == true)

        controller.navigateHistory(by: -1)
        #expect(controller.fileURL.lastPathComponent == "a.mmd")
        #expect(controller.fileListModel.canGoForward == true)
        #expect(controller.fileListModel.canGoBack == false)
    }

    @Test("戻る操作自体は新しい履歴を積まない")
    func navigatingHistoryDoesNotRecord() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "b.mmd", contents: "graph LR;")
        let fileB = fileA.deletingLastPathComponent().appendingPathComponent("b.mmd")
        let controller = ViewerWindowController(
            fileURL: fileA,
            zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "History"))
        )
        defer { controller.close() }
        controller.switchFile(to: fileB)

        controller.navigateHistory(by: -1) // a へ戻る
        controller.navigateHistory(by: 1)  // b へ進む

        // 破棄されずに往復できる = 戻る/進むで push されていない
        #expect(controller.fileURL.lastPathComponent == "b.mmd")
        #expect(controller.fileListModel.canGoForward == false)
        #expect(controller.fileListModel.canGoBack == true)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerTests`
Expected: FAIL（`value of type 'ViewerWindowController' has no member 'navigateHistory'` 等）

- [ ] **Step 3: 実装を書く**

**(3-1)** `ViewerWindowController` にプロパティを追加する。`fileListModel` 宣言（21 行目付近）の直後に:

```swift
    /// このタブの戻る/進むナビゲーション履歴（メモリ内のみ）。
    let history = NavigationHistory()
    /// 戻る/進む適用中は true。この間は recordHistory による再記録を抑止する。
    private var isApplyingHistory = false
```

**(3-2)** `init` の末尾、`updateToolbarVisibility()`（111 行目）の直後に初期エントリの記録を追加:

```swift
        recordHistory()
```

**(3-3)** `switchFile(to:)` の末尾、`onSwitchFile?(oldURL, newURL)`（239 行目）の直後に:

```swift
        recordHistory()
```

**(3-4)** `navigateToFolder(_:)` の末尾、メソッド最後の `}`（321 行目）の直前（if/else ブロックの後）に:

```swift
        recordHistory()
```

**(3-5)** `handleRename(to:)` の末尾、`onRename?(oldURL, newURL)`（211 行目）の直後に:

```swift
        history.renameOccurred(from: oldURL, to: newURL)
        refreshHistoryState()
```

**(3-6)** `navigateToFolder(_:)` の直後（321 行目の `}` の後）に、履歴操作の実装を追加:

```swift

    // MARK: - Navigation History

    /// サイドバーの戻る/進む・履歴メニューから呼ばれる。offset 負=戻る / 正=進む。
    func navigateHistory(by offset: Int) {
        guard let entry = history.move(by: offset) else { return }
        applyHistoryEntry(entry)
    }

    /// 現在の表示状態（ディレクトリ＋ファイル）を履歴に記録する。
    /// 戻る/進む適用中は抑止する。push は現在エントリと同一なら無視する。
    private func recordHistory() {
        guard !isApplyingHistory else { return }
        history.push(HistoryEntry(directory: fileListModel.currentDirectory, file: fileURL))
        refreshHistoryState()
    }

    /// 履歴エントリを表示へ適用する。再記録を抑止しつつ、ディレクトリと
    /// 表示ファイルを合わせる。switchFile の another-window 不変条件は尊重する。
    private func applyHistoryEntry(_ entry: HistoryEntry) {
        isApplyingHistory = true
        defer {
            isApplyingHistory = false
            refreshHistoryState()
        }
        if entry.directory.standardizedFileURL
            != fileListModel.currentDirectory.standardizedFileURL
        {
            fileListModel.currentDirectory = entry.directory
            fileListModel.entries = DirectoryLister.listEntries(
                in: entry.directory, sortOrder: fileListModel.sortOrder
            )
        }
        if let file = entry.file,
           file.standardizedFileURL != fileURL.standardizedFileURL
        {
            switchFile(to: file) // isApplyingHistory ガードにより recordHistory は抑止
        }
        refreshFileList()
    }

    /// 履歴状態をサイドバー（FileListModel）へ反映する。
    private func refreshHistoryState() {
        fileListModel.canGoBack = history.canGoBack
        fileListModel.canGoForward = history.canGoForward
        fileListModel.backHistory = history.backEntries()
        fileListModel.forwardHistory = history.forwardEntries()
    }
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter ViewerWindowControllerTests`
Expected: PASS（既存＋追加 3 tests）

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/App/ViewerWindowController.swift befold/Viewer/FileListView.swift befoldTests/ViewerWindowControllerTests.swift
git commit -m "feat: ViewerWindowController に戻る/進む履歴を組み込む"
```

---

### Task 3: サイドバー UI（ボタン + 履歴メニュー）とローカライズ

**Files:**
- Modify: `BefoldApp/befold/Viewer/FileListView.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `FileListModel.canGoBack/canGoForward/backHistory/forwardHistory`（Task 2 Step 0 で追加済み）、`ViewerWindowController.navigateHistory(by:)`。
- Produces: `FileListView` の新プロパティ `let onNavigateHistory: (Int) -> Void`。

> このタスクは主に UI 配線。View / 履歴メニューの見た目・長押し/右クリック挙動は自動テスト対象外（リリース前手動チェック）。ビルドが通り既存テストが回帰しないことを確認する。

- [ ] **Step 1: ローカライズキーを追加**

`BefoldApp/befold/Resources/Localizable.xcstrings` に 2 キーを追加する。`strings` オブジェクト内へ以下のエントリを挿入（既存キーと同じ構造）:

```json
    "sidebar.nav.back" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Back" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "戻る" } }
      }
    },
    "sidebar.nav.forward" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Forward" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "進む" } }
      }
    },
```

確認: `cd BefoldApp && swift test --filter LocalizationTests`
Expected: PASS（新キーが両言語を持つため回帰なし）

- [ ] **Step 2: `FileListView` にコールバックと履歴 UI を追加**

**(2-1)** `FileListView` のプロパティ（22-27 行目）に 1 つ追加:

```swift
    let onNavigateHistory: (Int) -> Void
```

**(2-2)** `header`（36-58 行目）を、先頭に戻る/進む `Menu` を置く形へ差し替える。既存の `HStack { Text(...) ... 並び順ボタン ... }` の **`Text(model.currentDirectory...)` の前**に以下を挿入:

```swift
            backForwardControls
```

そして `header` の直後に、以下のビューを追加する:

```swift
    /// サイドバー上部の戻る/進むコントロール。
    /// primaryAction=1 ステップ移動 / 長押し（menu 展開）・右クリックで履歴メニュー。
    private var backForwardControls: some View {
        HStack(spacing: 2) {
            Menu {
                historyMenuItems(model.backHistory, direction: -1)
            } label: {
                Image(systemName: "chevron.backward")
                    .foregroundStyle(.secondary)
            } primaryAction: {
                onNavigateHistory(-1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!model.canGoBack)
            .help(String(localized: "sidebar.nav.back", bundle: .l10n))
            .contextMenu { historyMenuItems(model.backHistory, direction: -1) }

            Menu {
                historyMenuItems(model.forwardHistory, direction: 1)
            } label: {
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.secondary)
            } primaryAction: {
                onNavigateHistory(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!model.canGoForward)
            .help(String(localized: "sidebar.nav.forward", bundle: .l10n))
            .contextMenu { historyMenuItems(model.forwardHistory, direction: 1) }
        }
    }

    /// 履歴メニューの項目群。direction は移動方向の符号（-1=戻る / 1=進む）。
    /// i 番目（0 始まり）は現在地から (i + 1) ステップ移動する。
    @ViewBuilder
    private func historyMenuItems(_ entries: [HistoryEntry], direction: Int) -> some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
            Button(historyLabel(entry)) {
                onNavigateHistory(direction * (index + 1))
            }
        }
    }

    /// 履歴メニュー項目のラベル。`ファイル名 — ディレクトリ名`。ファイルがなければディレクトリ名のみ。
    private func historyLabel(_ entry: HistoryEntry) -> String {
        let dir = entry.directory.lastPathComponent
        if let file = entry.file {
            return "\(file.lastPathComponent) — \(dir)"
        }
        return dir
    }
```

- [ ] **Step 3: `ViewerWindowController` で新コールバックを配線**

`makeSplitViewController()` 内の `FileListView(...)` 生成（129-141 行目）に `onNavigateHistory` を追加する。`onOpenInNewWindow:` クロージャの後に:

```swift
                onNavigateHistory: { [weak self] offset in
                    self?.navigateHistory(by: offset)
                }
```

（`FileListView` のメンバワイズ初期化はプロパティ宣言順に引数が並ぶため、`onNavigateHistory` は宣言位置（`onOpenInNewWindow` の後）に対応する引数位置へ置く。）

- [ ] **Step 4: ビルドと全テストで回帰がないことを確認**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功（警告のみ許容、エラーなし）

Run: `cd BefoldApp && swift test`
Expected: PASS（全スイート。特に `NavigationHistoryTests` / `ViewerWindowControllerTests` / `LocalizationTests`）

- [ ] **Step 5: `.xcodeproj` を再生成（Xcode 利用者向け）**

Run: `cd BefoldApp && xcodegen generate`
Expected: `Created project at ...befold.xcodeproj`

- [ ] **Step 6: コミット**

```bash
cd BefoldApp
git add befold/Viewer/FileListView.swift befold/App/ViewerWindowController.swift befold/Resources/Localizable.xcstrings befold.xcodeproj
git commit -m "feat: サイドバーに戻る/進むボタンと履歴メニューを追加する"
```

- [ ] **Step 7: 手動スモークチェック（リリース前）**

1. `swift run`（または `/run`）でアプリ起動。ホーム配下の `.mmd`/`.md` を開く。
2. サイドバーで複数ファイルを順に選択 → 戻るボタンで直前ファイルへ戻る／進むで戻れることを確認。
3. フォルダを移動（ダブルクリック/`l`）→ 戻るで元ディレクトリ＋元ファイルへ戻ることを確認。
4. 戻るボタンを **長押し** → 履歴メニュー（`ファイル名 — ディレクトリ名`）が出て任意項目へジャンプできることを確認。**右クリック**でも同じメニューが出ることを確認。
5. 履歴の先頭/末尾で対応するボタンが disabled になることを確認。
6. 戻った後に別ファイルを選択 → 進む履歴が破棄されることを確認。

---

## Self-Review

**1. Spec coverage:**
- 統合1本の履歴 → Task 1 `NavigationHistory`（単一スタック）✅
- タブごと → `ViewerWindowController` が `history` を1つ保持（Task 2）✅
- スナップショット `{directory, file?}` → `HistoryEntry`（Task 1）✅
- 非永続 → メモリ内のみ、永続化コードなし ✅
- 戻る/進むボタン（サイドバー上部・borderless） → Task 3 `backForwardControls` ✅
- 長押し + 右クリック履歴メニュー → `Menu(primaryAction:)` + `.contextMenu`（Task 3）✅
- ラベル `ファイル名 — ディレクトリ名` → `historyLabel`（Task 3）✅
- 進む履歴の破棄 → `push` の truncate（Task 1、テスト有）✅
- 重複防止 → `push` の同一判定（Task 1、テスト有）✅
- rename 追従 → `renameOccurred` + `handleRename` 連携（Task 1/2、テスト有）✅
- disabled 連動 → `canGoBack/canGoForward` + `.disabled`（Task 2/3）✅
- テスト（純ロジック網羅・@MainActor 統合・UI は手動）→ Task 1/2 自動、Task 3 Step 7 手動 ✅

**2. Placeholder scan:** TBD/TODO/曖昧指示なし。全コードステップに実コードを記載。✅

**3. Type consistency:**
- `navigateHistory(by:)`（Task 2 定義）＝ Task 3 配線 ＝ `onNavigateHistory` の呼び先で一致。✅
- `move(by:)` / `push` / `backEntries` / `forwardEntries` / `renameOccurred`（Task 1 定義）＝ Task 2 使用で一致。✅
- `canGoBack`/`canGoForward`/`backHistory`/`forwardHistory`（Task 2 Step 0 で FileListModel に定義）＝ Task 2 `refreshHistoryState` 代入 ＝ Task 3 View 参照で一致。✅
- `HistoryEntry(directory:file:)` の引数ラベルが全タスクで一致。✅

**エッジケース補足（実装時の注意、既存挙動を尊重）:**
- 履歴適用で `switchFile` の another-window 不変条件が働くと、対象ファイルが別ウィンドウで開いている場合は切替が中止される（選択のみ巻き戻る）。稀なケースとして許容。
- 存在しないディレクトリの履歴適用時、`DirectoryLister.listEntries` は列挙失敗で空配列を返す想定（クラッシュしない）。削除済みファイルは既存の `ViewerStore.isDeleted` 表示に委ねる。
