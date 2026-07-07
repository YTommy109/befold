# CLI インストール文言変更 と 削除ファイル処理簡略化 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** メニューの CLI インストール文言を汎用化し、削除ファイルのバナー表示を廃止してウィンドウ自動クローズに置き換える。

**Architecture:** Item 1 は `Localizable.xcstrings` の文字列変更のみ。Item 2 は `ViewerStore` にグレース期間付きの `onFileGone` コールバックを追加し、`ViewerWindowController` の `init` でウィンドウクローズに接続する。`isDeleted` は Swift 側の参照（Store / WebView / ContentView / Bridge / テスト）を **1 コミットで**除去し、どのコミットでもビルドが通る状態を保つ。存在しないファイルへの経路は「新規に開く」(`ViewerWindowManager.openViewer`) と「ウィンドウ内切替」(`performFileSwitch`) の両方でガードする。

**Tech Stack:** Swift 6 / AppKit + SwiftUI / WKWebView / Swift Testing

## Global Constraints

- macOS 14+ / Swift 6 strict concurrency
- `@MainActor @Observable` の `ViewerStore`
- テストは Swift Testing フレームワーク
- Conventional Commits + 日本語
- 各タスクのコミット時点で `swift build` / `swift test` が通ること（コンパイル不能なコミットを作らない）

---

### Task 1: CLI インストールメニューの文言変更

**Files:**
- Modify: `befold/Resources/Localizable.xcstrings:18-24`
- Test: `befoldTests/MainMenuBuilderTests.swift:135`（既存テストが通ることを確認）

**Interfaces:**
- Consumes: なし
- Produces: なし（文字列リソースのみ）

- [ ] **Step 1: `Localizable.xcstrings` の文言を変更する**

`menu.app.installCLI` のエントリを以下に変更する:

```json
"menu.app.installCLI" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Install Command Line Tool" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "コマンドラインツールをインストール" } }
  }
},
```

- [ ] **Step 2: テスト実行**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`

`MainMenuBuilderTests` の `installItem.title` アサーション（line 135）は
`localizedTitle("menu.app.installCLI")` で動的に取得するため、文言変更で壊れない。
全テスト PASS を確認する。

- [ ] **Step 3: コミット**

```bash
git add befold/Resources/Localizable.xcstrings
git commit -m "fix: CLI インストールメニューの文言を汎用表現に変更する"
```

---

### Task 2: Swift 側から isDeleted を除去し onFileGone を追加する

`isDeleted` は `ViewerStore` → `ViewerContentView` → `ViewerWebView` と鎖状に参照されて
いるため、このタスクで **Swift 側の全参照を一括で**変更する。分割するとコンパイル不能な
コミットができる。

**Files:**
- Modify: `befold/Viewer/ViewerStore.swift`
- Modify: `befold/Viewer/ViewerWebView.swift`
- Modify: `befold/Viewer/ViewerContentView.swift`
- Modify: `befold/Viewer/ViewerBridge.swift`
- Test: `befoldTests/ViewerStoreTests.swift`
- Modify: `befoldTests/ViewerStoreIntegrationTests.swift`
- Modify: `befoldTests/ViewerBridgeTests.swift:123`

**Interfaces:**
- Consumes: なし
- Produces:
  - `ViewerStore.onFileGone: (@MainActor @Sendable () -> Void)?` — ファイル消失確定時に発火するコールバック（Task 4 が使う）
  - `isDeleted` プロパティ、`ViewerWebView` の `isDeleted` パラメータ、`ViewerBridge.showDeletedBannerScript` は削除される

- [ ] **Step 1: ユニットテストを書き換える**

`ViewerStoreTests.swift` を以下のように変更する:

1. `openNonexistentFileMarksDeleted` (lines 45-54) → `openNonexistentFileFiresOnFileGoneAfterGrace` に変更する。
   `onFileGone` はグレース期間（0.3 秒）後に非同期発火するため、テストは async にして待つ:

```swift
@Test
func openNonexistentFileFiresOnFileGoneAfterGrace() async throws {
    let file = URL(fileURLWithPath: "/files/missing.mmd")
    let store = makeStore(reader: InMemoryFileReader())

    nonisolated(unsafe) var firedCount = 0
    store.onFileGone = { firedCount += 1 }
    store.openFile(file)
    // グレース期間中は発火しない
    #expect(firedCount == 0)

    try await Task.sleep(for: .seconds(0.5))
    #expect(firedCount == 1)

    store.close()
}
```

2. `watcherCallbackTracksDeletionAndRecreation` (lines 223-249) → `watcherCallbackCancelsFileGoneOnRecreation` に変更:

```swift
@Test
func watcherCallbackCancelsFileGoneOnRecreation() async throws {
    let file = URL(fileURLWithPath: "/files/test.mmd")
    let reader = InMemoryFileReader()
    reader.setFile("graph TD; A-->B", at: file)

    nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
    let store = ViewerStore(watcherFactory: { _, callback, _ in
        onChange = callback
        return MockFileWatcher()
    }, fileReader: reader)

    nonisolated(unsafe) var firedCount = 0
    store.onFileGone = { firedCount += 1 }
    store.openFile(file)
    #expect(firedCount == 0)

    // ファイル削除 → コールバック発火でグレース期間開始
    reader.setFile(nil, at: file)
    onChange?()

    // グレース期間内に再作成 → onFileGone は発火しない
    reader.setFile("graph TD; C-->D", at: file)
    onChange?()
    // グレース期間(0.3s)を過ぎても発火しないことを確認
    try await Task.sleep(for: .seconds(0.5))
    #expect(firedCount == 0)
    #expect(store.content == "graph TD; C-->D")

    store.close()
}
```

3. `watcherCallbackFiresOnFileGoneAfterGracePeriod` テストを追加:

```swift
@Test
func watcherCallbackFiresOnFileGoneAfterGracePeriod() async throws {
    let file = URL(fileURLWithPath: "/files/test.mmd")
    let reader = InMemoryFileReader()
    reader.setFile("graph TD; A-->B", at: file)

    nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
    let store = ViewerStore(watcherFactory: { _, callback, _ in
        onChange = callback
        return MockFileWatcher()
    }, fileReader: reader)

    nonisolated(unsafe) var firedCount = 0
    store.onFileGone = { firedCount += 1 }
    store.openFile(file)

    // ファイル削除 → コールバック発火
    reader.setFile(nil, at: file)
    onChange?()

    // グレース期間後に onFileGone が発火する
    try await Task.sleep(for: .seconds(0.5))
    #expect(firedCount == 1)

    store.close()
}
```

4. 再削除の検知が止まらないことのテストを追加（stale タスクによる検知停止のリグレッション防止）:

```swift
@Test
func fileGoneDetectionSurvivesRecreateAndRedelete() async throws {
    let file = URL(fileURLWithPath: "/files/test.mmd")
    let reader = InMemoryFileReader()
    reader.setFile("graph TD; A-->B", at: file)

    nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
    let store = ViewerStore(watcherFactory: { _, callback, _ in
        onChange = callback
        return MockFileWatcher()
    }, fileReader: reader)

    nonisolated(unsafe) var firedCount = 0
    store.onFileGone = { firedCount += 1 }
    store.openFile(file)

    // 削除 → グレース期間開始
    reader.setFile(nil, at: file)
    onChange?()
    // 監視イベントなしで再作成(発火直前の存在再確認だけで救済されるケース)。
    // グレースタスクは発火せずに完了する
    reader.setFile("graph TD; C-->D", at: file)
    try await Task.sleep(for: .seconds(0.5))
    #expect(firedCount == 0)

    // 再削除 → 完了済みの stale タスクが検知を塞いでいないこと
    reader.setFile(nil, at: file)
    onChange?()
    try await Task.sleep(for: .seconds(0.5))
    #expect(firedCount == 1)

    store.close()
}
```

5. 他のテストから `!store.isDeleted` のアサーションをすべて削除する。対象:
   - `openFileByType` (line 39)
   - `openEmptyFile` (line 66)
   - `openBinaryFileMarksUnsupported` (line 105)
   - `openOversizedFileMarksUnsupportedWithoutLoading` (line 138)
   - `watcherRenameUpdatesPathAndReloadsContent` (line 277)
   - `openImageFileLoadsBase64Content` (line 297)
   - `openPdfFileLoadsBase64Content` (line 316)
   - `imageReadFailureMarksUnsupported` (line 398)

- [ ] **Step 2: テスト実行して red 状態を確認する**

Run: `cd BefoldApp && swift test --filter ViewerStoreTests`

Expected: **コンパイルエラー**（`value of type 'ViewerStore' has no member 'onFileGone'`）。
新テストが参照する `onFileGone` はまだ存在しないため、テストモジュール全体がビルドに
失敗する。これがこのタスクの red 状態（個別テストの FAIL ではない）。

- [ ] **Step 3: `ViewerStore.swift` を変更する**

以下の変更を行う:

1. `isDeleted` プロパティ (line 26) を削除する
2. `onFileGone` コールバックと `fileGoneTask` を追加する:

```swift
/// 監視中のファイルが削除されたことが確定したときに呼ばれるコールバック。
/// グレース期間(0.3 秒)中に再作成されなかった場合に発火する。
var onFileGone: (@MainActor @Sendable () -> Void)?

/// 削除確認のグレース期間タスク。再作成されたらキャンセルする。
private var fileGoneTask: Task<Void, Never>?
```

3. `loadContent()` のファイル不在ブロックを変更する。変更前:

```swift
guard fileReader.fileExists(at: resolved) else {
    isDeleted = true
    isUnsupported = false
    return
}
isDeleted = false
```

変更後:

```swift
guard fileReader.fileExists(at: resolved) else {
    scheduleFileGone()
    return
}
fileGoneTask?.cancel()
fileGoneTask = nil
```

4. `scheduleFileGone()` メソッドを追加する。
   **必ず cancel-and-replace にする**: 「既にタスクがあれば何もしない」ガードにすると、
   発火せずに完了した stale タスクが残ったとき（再作成救済の直後に再削除された場合）に
   以後の削除検知が永久に止まる。

```swift
/// グレース期間後にファイルの不在を再確認し、確定したら onFileGone を発火する。
/// 常に張り直す(古いタスクをキャンセルして置き換える)ことで、発火せず完了した
/// タスクが残って以後の検知を塞ぐことを防ぐ。
private func scheduleFileGone() {
    fileGoneTask?.cancel()
    fileGoneTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(0.3))
        guard let self, !Task.isCancelled else { return }
        guard let filePath else { return }
        guard !fileReader.fileExists(at: filePath.resolvingSymlinksInPath()) else { return }
        onFileGone?()
    }
}
```

5. `openFile(_:)` の冒頭で pending タスクをキャンセルする:

```swift
func openFile(_ url: URL) {
    fileGoneTask?.cancel()
    fileGoneTask = nil
    fileWatcher?.stop()
    filePath = url
    fileType = FileType(url: url)
    loadContent()
    // ...(既存の makeWatcher 呼び出しはそのまま)
}
```

6. `close()` を変更する:

```swift
func close() {
    fileGoneTask?.cancel()
    fileGoneTask = nil
    fileWatcher?.stop()
    fileWatcher = nil
}
```

- [ ] **Step 4: `ViewerBridge.swift` から `showDeletedBannerScript` を削除する**

line 17 を削除:

```swift
static let showDeletedBannerScript = "showDeletedBanner()"
```

- [ ] **Step 5: `ViewerWebView.swift` から `isDeleted` 関連を削除する**

1. `isDeleted` プロパティ (line 9) を削除
2. `updateNSView` の `isDeleted: isDeleted,` 引数 (line 86) を削除
3. `Coordinator` の `lastWasDeleted` プロパティ (line 140) を削除
4. `updateContent` メソッドのシグネチャから `isDeleted: Bool,` パラメータを削除
5. `updateContent` 内の `if isDeleted { ... }` ブロック (lines 233-252) を削除
6. `updateContent` 内の `lastWasDeleted = false` の行 (lines 256, 300, 314) を削除
7. `updateContent` 内の `|| lastWasDeleted == true` の条件 (line 310) を削除
8. `handleNavigationFailure` 内のバナー注入 (line 199) を削除する。
   フォールバック自体（viewer.html への復帰）はナビゲーション失敗からの復旧として残す。
   削除起因の失敗は `onFileGone` がウィンドウを閉じるため、ここでの表示は不要
   （削除以外の一時的失敗の挙動は仕様書「既知の制限」参照）:

```swift
private func handleNavigationFailure(webView: WKWebView) {
    pendingPageZoom = nil
    if isDirectHTMLMode {
        isDirectHTMLMode = false
        webViewProxy?.isDirectHTMLMode = false
        lastDirectHTMLPath = nil
        lastRenderedContent = nil
        lastRenderedFileType = nil
        // 削除起因の失敗は onFileGone がウィンドウを閉じるため、ここでは
        // viewer.html へ戻すだけでよい
        reloadViewerHTML(webView: webView) {}
    } else {
        isReady = true
        pendingUpdate?()
        pendingUpdate = nil
    }
}
```

- [ ] **Step 6: `ViewerContentView.swift` から `isDeleted` の受け渡しを削除する**

line 31 の `isDeleted: store.isDeleted,` を削除する。

- [ ] **Step 7: `ViewerBridgeTests.swift` のブリッジ契約テストを修正する**

line 123 を削除:

```swift
#expect(html.contains("function showDeletedBanner()"))
```

- [ ] **Step 8: 統合テストを書き換える**

`ViewerStoreIntegrationTests.swift` の `deletingWatchedFileMarksDeleted` を書き換える:

```swift
@Test(.timeLimit(.minutes(1)))
func deletingWatchedFileFiresOnFileGone() async throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

    let store = ViewerStore()
    nonisolated(unsafe) var firedCount = 0
    store.onFileGone = { firedCount += 1 }
    store.openFile(file)
    #expect(firedCount == 0)

    try await Task.sleep(for: .seconds(0.3))
    try FileManager.default.removeItem(at: file)

    try await Task.sleep(for: .seconds(3))
    #expect(firedCount == 1)

    store.close()
}
```

- [ ] **Step 9: 全テスト実行して PASS を確認する**

Run: `cd BefoldApp && swift test`

Expected: 全テスト PASS（このタスクで Swift 側の `isDeleted` 参照はゼロになっている。
確認: `grep -rn "isDeleted\|showDeletedBanner" BefoldApp/befold --include='*.swift'` が 0 件）。

- [ ] **Step 10: コミット**

```bash
git add befold/Viewer/ViewerStore.swift befold/Viewer/ViewerWebView.swift befold/Viewer/ViewerContentView.swift befold/Viewer/ViewerBridge.swift befoldTests/ViewerStoreTests.swift befoldTests/ViewerStoreIntegrationTests.swift befoldTests/ViewerBridgeTests.swift
git commit -m "feat: isDeleted フラグをグレース期間付き onFileGone コールバックに置き換える"
```

---

### Task 3: viewer.html / style.css から削除バナーの HTML/JS/CSS を除去する

**Files:**
- Modify: `befold/Resources/viewer.html`
- Modify: `befold/Resources/style.css`

**Interfaces:**
- Consumes: Task 2 で Swift 側から `showDeletedBanner()` の呼び出しが除去済み
- Produces: なし

- [ ] **Step 1: `viewer.html` から削除バナー関連を除去する**

1. line 27 の `<div id="mmd-deleted-banner" class="mmd-deleted-banner">deleted</div>` を削除
2. lines 567-576 の `showDeletedBanner()` / `hideDeletedBanner()` 関数定義（`--- Deleted Banner ---` コメント含む）を削除
3. line 413 の `hideDeletedBanner();` 呼び出しを削除（`render()` 関数内）
4. lines 341-346 のダークモード再描画時の削除バナー復元ロジックを削除:

変更前:

```javascript
if (_lastContent !== null) {
    var wasDeleted = document.body.classList.contains('mmd-deleted');
    render(_lastContent, _lastType, _lastLang);
    // render() は先頭で hideDeletedBanner() を呼ぶため、削除状態を復元する。
    if (wasDeleted) { showDeletedBanner(); }
}
```

変更後:

```javascript
if (_lastContent !== null) {
    render(_lastContent, _lastType, _lastLang);
}
```

- [ ] **Step 2: `style.css` から削除バナー関連を除去する**

1. `--bg-deleted-tint` CSS 変数を削除:
   - light テーマ (line 45): `--bg-deleted-tint: rgba(0, 0, 0, 0.09);`（直前のコメント行含む）
   - dark テーマ (line 72): `--bg-deleted-tint: rgba(255, 255, 255, 0.053);`（直前のコメント行含む）
2. `body.mmd-deleted` ルール (lines 113-117) とそのコメントを削除
3. `.mmd-deleted-banner` ルール (lines 139-157) を削除

- [ ] **Step 3: `--banner-fg` CSS 変数の使用箇所を確認して削除する**

Run: `grep -n 'banner-fg' BefoldApp/befold/Resources/style.css`

使用箇所は定義 (lines 57, 84) と `.mmd-deleted-banner` (line 155) のみ
（レビュー時点で確認済み）。`.mmd-deleted-banner` の削除で未使用になるため、
定義 2 箇所も削除する。

- [ ] **Step 4: テスト実行**

Run: `cd BefoldApp && swift test`

Expected: 全テスト PASS（ViewerBridgeTests の `showDeletedBanner` チェックは Task 2 で削除済み）。

- [ ] **Step 5: コミット**

```bash
git add befold/Resources/viewer.html befold/Resources/style.css
git commit -m "refactor: viewer.html / style.css から削除バナーの HTML/JS/CSS を除去する"
```

---

### Task 4: ウィンドウクローズと存在チェックの統合

**Files:**
- Modify: `befold/App/ViewerWindowController.swift`
- Modify: `befold/App/ViewerWindowManager.swift`

**Interfaces:**
- Consumes:
  - `ViewerStore.onFileGone: (@MainActor @Sendable () -> Void)?` (Task 2)
- Produces: なし

- [ ] **Step 1: `ViewerWindowController` の init で `onFileGone` をウィンドウクローズに接続する**

**注意: `ViewerWindowController` に `windowDidLoad()` は存在しない**。ウィンドウを
`super.init(window:)` に渡して生成しているため、NSWindowController は `windowDidLoad`
を呼ばない（nib/storyboard ロード時のみ呼ばれる）。配線は既存の `store.onFileRenamed`
の設定と同じ場所（`init` 内、`store.openFile(fileURL)` の直前、
ViewerWindowController.swift:110 付近）に置く:

```swift
store.onFileGone = { [weak self] in
    self?.window?.close()
}
store.onFileRenamed = { [weak self] newURL in
    self?.handleRename(to: newURL)
}
store.openFile(fileURL)
```

- [ ] **Step 2: `ViewerWindowManager.openViewer(for:)` にファイル存在チェックを追加する**

`ViewerWindowManager.swift` の `openViewer(for:forceSidebarVisible:)` メソッドの
冒頭にガードを追加する:

```swift
func openViewer(for url: URL, forceSidebarVisible: Bool = false) {
    guard FileManager.default.fileExists(atPath: url.path) else {
        showFileNotFoundAlert(path: url.path)
        return
    }

    let key = url.normalizedPathKey
    // ... 既存ロジック
}
```

`showFileNotFoundAlert` メソッドを `ViewerWindowManager` に追加する。
まだウィンドウが無い状態で表示するため `runModal()` を使う
（`ViewerWindowController.showFileNotFoundAlert` はウィンドウ内シート表示のためそのまま残す）:

```swift
private func showFileNotFoundAlert(path: String) {
    let alert = NSAlert()
    alert.messageText = String(
        localized: "alert.fileNotFound.message",
        defaultValue: "File Not Found",
        bundle: .l10n
    )
    alert.informativeText = path
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
```

- [ ] **Step 3: `performFileSwitch(to:)` に存在ガードを追加する**

サイドバー選択 (`switchFile`)・履歴ナビゲーション (`applyHistoryEntry`) は
`ViewerWindowManager.openViewer` を通らず `store.openFile` を直接呼ぶ
(ViewerWindowController.swift:343-351)。ガードなしだと消えたファイルへの切替が
`onFileGone` 経由で**ウィンドウごと閉じてしまう**ため、共通経路である
`performFileSwitch` の入り口でチェックする:

```swift
/// switchFile と applyHistoryEntry が共有するファイル切替の実処理。
/// ビューモードのリセット、URL 更新、コンテンツ読込、ズーム適用、コールバック通知を行う。
/// 切替先が存在しない場合はアラートを表示して false を返す(状態は変更しない)。
@discardableResult
private func performFileSwitch(to newURL: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: newURL.path) else {
        showFileNotFoundAlert(path: newURL.path)
        return false
    }
    let oldURL = fileURL
    resetSourceMode()
    applyURLToWindow(newURL)
    store.openFile(newURL)
    updateToolbarVisibility()
    applyStoredZoomToWebView()
    onSwitchFile?(oldURL, newURL)
    return true
}
```

呼び出し側も失敗時に後続の状態更新をしないように変更する。

`switchFile(to:)` (line 222 付近):

```swift
func switchFile(to newURL: URL) {
    let oldURL = fileURL
    guard newURL != oldURL else { return }
    if isFileOpenInAnotherWindow?(newURL) == true {
        focusWindowForFile?(newURL)
        fileListModel.selection = oldURL
        return
    }
    guard performFileSwitch(to: newURL) else {
        fileListModel.selection = oldURL
        return
    }
    // ...(既存の fileListModel 更新処理はそのまま)
}
```

`applyHistoryEntry(_:)` (line 355 付近) の `performFileSwitch(to: file)` 呼び出し:

```swift
if let file = entry.file,
   file.normalizedPathKey != fileURL.normalizedPathKey
{
    guard performFileSwitch(to: file) else { return false }
}
```

- [ ] **Step 4: ビルド確認**

Run: `cd BefoldApp && swift build`

Expected: コンパイル PASS。

- [ ] **Step 5: テスト実行**

Run: `cd BefoldApp && swift test`

Expected: 全テスト PASS。

- [ ] **Step 6: コミット**

```bash
git add befold/App/ViewerWindowController.swift befold/App/ViewerWindowManager.swift
git commit -m "feat: ファイル削除時にウィンドウを閉じ、存在しないファイルのオープンをエラー表示する"
```

---

### Task 5: coding_rule.md を onFileGone 方式に更新する

`docs/dev/coding_rule.md` は規範的な指示ドキュメントであり、`isDeleted` を規約として
記載したまま残すと将来の実装者が削除済みの仕組みを再導入してしまう。

**Files:**
- Modify: `docs/dev/coding_rule.md`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: `isDeleted` への言及を更新する**

Run: `grep -n 'isDeleted' docs/dev/coding_rule.md`

現時点の該当箇所は 3 つ（実行時に再確認すること）:

1. line 130 の命名例: `メソッド・プロパティ: lowerCamelCase（openFile, isDeleted）`
   → `isDeleted` を現存するプロパティに差し替える: `（openFile, isUnsupported）`
2. line 326 のテスト例: `#expect(!store.isDeleted)` を含むコード例
   → 前後を読み、現存するテストの例（例: `#expect(store.isUnsupported)`）に差し替える
3. line 374 のエラーハンドリング規約: `ファイル削除検出は isDeleted フラグで UI に伝搬する`
   → `ファイル削除はグレース期間(0.3 秒)後に onFileGone コールバックで通知し、ウィンドウを閉じる` に変更

- [ ] **Step 2: コミット**

```bash
git add docs/dev/coding_rule.md
git commit -m "docs: コーディング規約の削除検出の記述を onFileGone 方式に更新する"
```

---

### Task 6: 手動スモークテスト

**Files:** なし（動作確認のみ）

- [ ] **Step 1: アプリをビルドして起動する**

Run: `cd BefoldApp && swift build`

アプリを起動して以下を確認する。

- [ ] **Step 2: CLI インストールメニュー文言を確認する**

メニューバー → befold → 「コマンドラインツールをインストール」が表示されていることを確認する。

- [ ] **Step 3: 削除検知 → ウィンドウクローズを確認する**

1. テスト用 `.mmd` ファイルを作成して befold で開く
2. ターミナルからファイルを削除する: `rm /path/to/test.mmd`
3. 約 0.5 秒後にウィンドウが自動的に閉じることを確認する

- [ ] **Step 4: アトミック保存での復活を確認する**

1. テスト用 `.mmd` ファイルを作成して befold で開く
2. テキストエディタで編集・保存する
3. ウィンドウが閉じず、内容が更新されることを確認する

- [ ] **Step 5: 存在しないファイルへのオープンをエラー確認する**

1. ターミナルから存在しないファイルを指定して開く: `befold /tmp/nonexistent.mmd`
2. 「File Not Found」アラートが表示され、ウィンドウは開かないことを確認する

- [ ] **Step 6: サイドバーからの切替で消えたファイルを選んだ場合を確認する**

1. 同じフォルダに 2 つの `.mmd` ファイルを作成し、片方を befold で開く
2. ターミナルからもう片方を削除する（サイドバーには残ったままの状態を作る）
3. サイドバーで削除済みファイルをクリックする
4. 「File Not Found」アラートがシート表示され、**ウィンドウは閉じない**ことを確認する
