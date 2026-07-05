# File List Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ウィンドウの左側にリサイズ・開閉可能なサイドバーを追加し、開いたファイルの親ディレクトリ内の対応ファイル一覧を表示する。サイドバーでファイルをクリックすると同じウィンドウ内で表示を切り替える。

**Architecture:** `NSSplitViewController` を使い、sidebar + content の 2 ペインを構成する。サイドバーには SwiftUI `List` をホストし、`FileType.allExtensions` でフィルタしたファイル一覧を表示する。ファイル選択で `ViewerStore.openFile()` を呼び、ウィンドウメタデータも更新する。

**Tech Stack:** Swift 6 / AppKit (`NSSplitViewController`) / SwiftUI (`List`) / Swift Testing

## Global Constraints

- macOS 14+
- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- テスト関数名は英語 camelCase、日本語は `@Test("...")` 表示名
- Conventional Commits + 日本語
- `FileType.allExtensions` が対応拡張子の単一情報源

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `mmdview/Viewer/DirectoryLister.swift` | 指定ディレクトリ内の対応ファイル一覧取得 |
| Create | `mmdview/Viewer/FileListView.swift` | SwiftUI List でファイル名を表示する View |
| Create | `mmdview/App/ViewerSplitViewController.swift` | NSSplitViewController サブクラス（sidebar + content） |
| Modify | `mmdview/App/ViewerWindowController.swift` | contentViewController を SplitVC に変更、switchFile 追加 |
| Modify | `mmdview/App/ViewerWindowManager.swift` | onSwitchFile コールバック処理 |
| Modify | `mmdview/App/MainMenuBuilder.swift` | View メニューに Toggle Sidebar 追加 |
| Modify | `mmdview/Resources/Localizable.xcstrings` | menu.view.toggleSidebar のローカライズ |
| Create | `mmdviewTests/DirectoryListerTests.swift` | DirectoryLister のテスト |

---

### Task 1: DirectoryLister — ディレクトリ内の対応ファイル一覧取得

**Files:**
- Create: `MmdviewApp/mmdview/Viewer/DirectoryLister.swift`
- Create: `MmdviewApp/mmdviewTests/DirectoryListerTests.swift`

**Interfaces:**
- Consumes: `FileType.allExtensions: [String]`
- Produces: `DirectoryLister.listFiles(in directory: URL) -> [URL]`

- [ ] **Step 1: テストファイルを作成する**

```swift
// MmdviewApp/mmdviewTests/DirectoryListerTests.swift
import Foundation
@testable import mmdview
import Testing

@Suite
struct DirectoryListerTests {
    @Test("対応拡張子のファイルだけが返される")
    func listFilesFiltersByExtension() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let mmd = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let md = try tmp.file(named: "readme.md", contents: "# Hi")
        _ = try tmp.file(named: "photo.png", contents: "binary")
        _ = try tmp.file(named: "data.csv", contents: "a,b")

        let result = DirectoryLister.listFiles(in: tmp.url)

        let names = result.map(\.lastPathComponent)
        #expect(names.contains("diagram.mmd"))
        #expect(names.contains("readme.md"))
        #expect(!names.contains("photo.png"))
        #expect(!names.contains("data.csv"))
    }

    @Test("結果がファイル名でローカライズソートされる")
    func listFilesSortsByName() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "c.mmd", contents: "")
        _ = try tmp.file(named: "a.mmd", contents: "")
        _ = try tmp.file(named: "b.mmd", contents: "")

        let result = DirectoryLister.listFiles(in: tmp.url)

        #expect(result.map(\.lastPathComponent) == ["a.mmd", "b.mmd", "c.mmd"])
    }

    @Test("隠しファイルは除外される")
    func listFilesExcludesHidden() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "")
        _ = try tmp.file(named: "visible.mmd", contents: "")

        let result = DirectoryLister.listFiles(in: tmp.url)

        #expect(result.map(\.lastPathComponent) == ["visible.mmd"])
    }

    @Test("存在しないディレクトリでは空配列を返す")
    func listFilesReturnsEmptyForMissingDir() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let result = DirectoryLister.listFiles(in: missing)
        #expect(result.isEmpty)
    }
}
```

- [ ] **Step 2: テストがコンパイルエラーで失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter DirectoryListerTests 2>&1 | tail -5`
Expected: コンパイルエラー（`DirectoryLister` が未定義）

- [ ] **Step 3: DirectoryLister を実装する**

```swift
// MmdviewApp/mmdview/Viewer/DirectoryLister.swift
import Foundation

enum DirectoryLister {
    static func listFiles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let extensions = Set(FileType.allExtensions)
        return contents
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter DirectoryListerTests 2>&1 | tail -5`
Expected: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add MmdviewApp/mmdview/Viewer/DirectoryLister.swift MmdviewApp/mmdviewTests/DirectoryListerTests.swift
git commit -m "feat: ディレクトリ内の対応ファイル一覧を取得する DirectoryLister を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: FileListView — サイドバーの SwiftUI ビュー

**Files:**
- Create: `MmdviewApp/mmdview/Viewer/FileListView.swift`

**Interfaces:**
- Consumes: `DirectoryLister.listFiles(in:) -> [URL]`
- Produces: `FileListView` — `files: [URL]`, `selection: Binding<URL?>`, `onSelect: (URL) -> Void`

- [ ] **Step 1: FileListView を作成する**

```swift
// MmdviewApp/mmdview/Viewer/FileListView.swift
import SwiftUI

struct FileListView: View {
    let files: [URL]
    @Binding var selection: URL?
    let onSelect: (URL) -> Void

    var body: some View {
        List(files, id: \.self, selection: $selection) { file in
            Label {
                Text(file.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        }
        .onChange(of: selection) { _, newValue in
            if let url = newValue {
                onSelect(url)
            }
        }
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `cd MmdviewApp && swift build 2>&1 | tail -5`
Expected: ビルド成功

- [ ] **Step 3: コミットする**

```bash
git add MmdviewApp/mmdview/Viewer/FileListView.swift
git commit -m "feat: サイドバー用のファイル一覧 SwiftUI ビューを追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: ViewerSplitViewController — NSSplitViewController サブクラス

**Files:**
- Create: `MmdviewApp/mmdview/App/ViewerSplitViewController.swift`

**Interfaces:**
- Consumes: `FileListView`, `ViewerContentView`
- Produces: `ViewerSplitViewController` — `init(sidebarContent:mainContent:)`, sidebar の開閉状態

- [ ] **Step 1: ViewerSplitViewController を作成する**

```swift
// MmdviewApp/mmdview/App/ViewerSplitViewController.swift
import AppKit
import SwiftUI

final class ViewerSplitViewController: NSSplitViewController {
    init(sidebarView: NSView, mainView: NSView) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSViewController())
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = true
        sidebarItem.viewController.view = sidebarView

        let contentItem = NSSplitViewItem(viewController: NSViewController())
        contentItem.viewController.view = mainView

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        splitView.autosaveName = "ViewerSplitView"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `cd MmdviewApp && swift build 2>&1 | tail -5`
Expected: ビルド成功

- [ ] **Step 3: コミットする**

```bash
git add MmdviewApp/mmdview/App/ViewerSplitViewController.swift
git commit -m "feat: サイドバー付き NSSplitViewController を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: ViewerWindowController — SplitVC 統合と switchFile

**Files:**
- Modify: `MmdviewApp/mmdview/App/ViewerWindowController.swift`
- Modify: `MmdviewApp/mmdviewTests/ViewerWindowControllerTests.swift`

**Interfaces:**
- Consumes: `ViewerSplitViewController`, `DirectoryLister.listFiles(in:)`, `FileListView`, `ViewerContentView`
- Produces: `ViewerWindowController.switchFile(to:)`, `ViewerWindowController.onSwitchFile: ((_ old: URL, _ new: URL) -> Void)?`

- [ ] **Step 1: switchFile のテストを追加する**

`MmdviewApp/mmdviewTests/ViewerWindowControllerTests.swift` に以下を追加:

```swift
@Test("switchFile でファイル URL とウィンドウタイトルが更新される")
func switchFileUpdatesFileURLAndTitle() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
    let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
    let controller = ViewerWindowController(
        fileURL: file1,
        zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
    )
    defer { controller.close() }

    controller.switchFile(to: file2)

    #expect(controller.fileURL == file2)
    #expect(controller.window?.title == "second.mmd")
    #expect(controller.window?.representedURL == file2)
}

@Test("switchFile で onSwitchFile コールバックが旧・新 URL で呼ばれる")
func switchFileInvokesCallback() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
    let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
    let controller = ViewerWindowController(
        fileURL: file1,
        zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
    )
    defer { controller.close() }
    var callbackArgs: (old: URL, new: URL)?
    controller.onSwitchFile = { old, new in callbackArgs = (old, new) }

    controller.switchFile(to: file2)

    #expect(callbackArgs?.old == file1)
    #expect(callbackArgs?.new == file2)
}

@Test("switchFile で同じファイルを選んでも何も起きない")
func switchFileIgnoresSameFile() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
    let controller = ViewerWindowController(
        fileURL: file,
        zoomStore: ZoomStore(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerTests"))
    )
    defer { controller.close() }
    var called = false
    controller.onSwitchFile = { _, _ in called = true }

    controller.switchFile(to: file)

    #expect(!called)
}
```

- [ ] **Step 2: テストがコンパイルエラーで失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerWindowControllerTests 2>&1 | tail -5`
Expected: コンパイルエラー（`switchFile` / `onSwitchFile` が未定義）

- [ ] **Step 3: ViewerWindowController を変更する**

`MmdviewApp/mmdview/App/ViewerWindowController.swift` を変更:

**3a.** `onSwitchFile` コールバックプロパティを追加（`onBecomeKey` の下に）:

```swift
var onSwitchFile: ((_ old: URL, _ new: URL) -> Void)?
```

**3b.** `init(fileURL:zoomStore:)` の `contentView` 構築部分を変更。
既存の `NSHostingView(rootView: contentView)` 代入を以下に置き換える:

```swift
let files = DirectoryLister.listFiles(in: fileURL.deletingLastPathComponent())
let sidebarView = NSHostingView(
    rootView: FileListView(
        files: files,
        selection: .constant(fileURL),
        onSelect: { [weak self] url in self?.switchFile(to: url) }
    )
)
let mainView = NSHostingView(rootView: contentView)
let splitVC = ViewerSplitViewController(sidebarView: sidebarView, mainView: mainView)
window.contentViewController = splitVC
```

注意: `window.contentView = NSHostingView(rootView: contentView)` の行を削除し、上記に置き換える。

**3c.** `switchFile(to:)` メソッドを追加（`handleRename` の後に）:

```swift
func switchFile(to newURL: URL) {
    let oldURL = fileURL
    guard newURL != oldURL else { return }
    fileURL = newURL
    store.openFile(newURL)

    if let window {
        window.title = newURL.lastPathComponent
        window.representedURL = newURL
        let oldAutosaveName = oldURL.viewerFrameAutosaveName
        let newAutosaveName = newURL.viewerFrameAutosaveName
        NSWindow.removeFrame(usingName: oldAutosaveName)
        window.saveFrame(usingName: newAutosaveName)
        windowFrameAutosaveName = newAutosaveName
    }

    zoomStore.migrateZoom(from: oldURL, to: newURL)
    onSwitchFile?(oldURL, newURL)
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerWindowControllerTests 2>&1 | tail -5`
Expected: 全テスト PASS

- [ ] **Step 5: 全テストが通ることを確認する**

Run: `cd MmdviewApp && swift test 2>&1 | tail -10`
Expected: 全テスト PASS

- [ ] **Step 6: コミットする**

```bash
git add MmdviewApp/mmdview/App/ViewerWindowController.swift MmdviewApp/mmdviewTests/ViewerWindowControllerTests.swift
git commit -m "feat: ViewerWindowController に NSSplitViewController と switchFile を統合する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: ViewerWindowManager — onSwitchFile コールバック処理

**Files:**
- Modify: `MmdviewApp/mmdview/App/ViewerWindowManager.swift`
- Modify: `MmdviewApp/mmdviewTests/ViewerWindowManagerTests.swift`

**Interfaces:**
- Consumes: `ViewerWindowController.onSwitchFile`
- Produces: `bindCallbacks` 内の `onSwitchFile` ハンドリング

- [ ] **Step 1: テストを追加する**

`MmdviewApp/mmdviewTests/ViewerWindowManagerTests.swift` に以下を追加:

```swift
@Test("switchFile で管理辞書のキーが付け替わりセッション記録が更新される")
func switchFileUpdatesControllerKeyAndSession() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
    let file2 = try tmp.file(named: "second.mmd", contents: "graph LR;")
    let defaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
    let sessionStore = SessionStore(defaults: defaults)
    let manager = ViewerWindowManager(
        sessionStore: sessionStore,
        zoomStore: ZoomStore(defaults: defaults),
        recentDocumentsStore: RecentDocumentsStore(defaults: defaults)
    )

    manager.openViewer(for: file1)
    #expect(manager.controllers[file1.normalizedPathKey] != nil)

    manager.controllers[file1.normalizedPathKey]?.onSwitchFile?(file1, file2)

    #expect(manager.controllers[file1.normalizedPathKey] == nil)
    #expect(manager.controllers[file2.normalizedPathKey] != nil)
    let savedPaths = sessionStore.savedURLs().map(\.normalizedPathKey)
    #expect(savedPaths.contains(file2.normalizedPathKey))
    #expect(!savedPaths.contains(file1.normalizedPathKey))
    manager.controllers.values.forEach { $0.close() }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerWindowManagerTests/switchFileUpdatesControllerKeyAndSession 2>&1 | tail -5`
Expected: FAIL（`onSwitchFile` が nil で、コールバックが発火しない）

- [ ] **Step 3: ViewerWindowManager.bindCallbacks に onSwitchFile を追加する**

`MmdviewApp/mmdview/App/ViewerWindowManager.swift` の `bindCallbacks` メソッド内、
`controller.onRename = { ... }` ブロックの後に以下を追加:

```swift
controller.onSwitchFile = { [weak self, weak controller] oldURL, newURL in
    guard let self, let controller else { return }
    let oldKey = oldURL.normalizedPathKey
    let newKey = newURL.normalizedPathKey
    if controllers[oldKey] === controller {
        controllers.removeValue(forKey: oldKey)
    }
    controllers[newKey] = controller
    sessionStore.noteClosed(oldURL)
    sessionStore.noteOpened(newURL)
    recentDocumentsStore.noteOpened(newURL)
    NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
    bindCallbacks(for: controller, key: newKey, url: newURL)
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter ViewerWindowManagerTests 2>&1 | tail -5`
Expected: 全テスト PASS

- [ ] **Step 5: コミットする**

```bash
git add MmdviewApp/mmdview/App/ViewerWindowManager.swift MmdviewApp/mmdviewTests/ViewerWindowManagerTests.swift
git commit -m "feat: ViewerWindowManager に onSwitchFile コールバック処理を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 6: MainMenuBuilder — Toggle Sidebar メニュー項目とローカライズ

**Files:**
- Modify: `MmdviewApp/mmdview/App/MainMenuBuilder.swift`
- Modify: `MmdviewApp/mmdview/Resources/Localizable.xcstrings`
- Modify: `MmdviewApp/mmdviewTests/MainMenuBuilderTests.swift`（既存テストにメニュー項目の検証を追加）

**Interfaces:**
- Consumes: なし
- Produces: View メニューの「Toggle Sidebar」項目（`Cmd+Opt+S`）

- [ ] **Step 1: MainMenuBuilder の View メニューに Toggle Sidebar を追加する**

`MmdviewApp/mmdview/App/MainMenuBuilder.swift` の `makeViewMenuItem()` メソッド内、
ズーム項目の後（`menu.addItem(.separator())` の前）にセパレータと Toggle Sidebar を追加する。

既存の:
```swift
menu.addItem(.separator())
let fullScreen = menu.addItem(
```

を以下に変更:
```swift
menu.addItem(.separator())
let toggleSidebar = menu.addItem(
    withTitle: String(localized: "menu.view.toggleSidebar", bundle: .l10n),
    action: #selector(NSSplitViewController.toggleSidebar(_:)),
    keyEquivalent: "s"
)
toggleSidebar.keyEquivalentModifierMask = [.command, .option]
menu.addItem(.separator())
let fullScreen = menu.addItem(
```

- [ ] **Step 2: Localizable.xcstrings にエントリを追加する**

`MmdviewApp/mmdview/Resources/Localizable.xcstrings` に `menu.view.toggleSidebar` キーを追加:

- en: `"Toggle Sidebar"`（defaultLocalization が en なので `extractionState: "manual"` で追加）
- ja: `"サイドバーを表示/非表示"`

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd MmdviewApp && swift build 2>&1 | tail -5`
Expected: ビルド成功

- [ ] **Step 4: 既存の MainMenuBuilder テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter MainMenuBuilderTests 2>&1 | tail -5`
Expected: 全テスト PASS

- [ ] **Step 5: 全テストが通ることを確認する**

Run: `cd MmdviewApp && swift test 2>&1 | tail -10`
Expected: 全テスト PASS（LocalizationTests が新キーを自動検出する可能性あり）

- [ ] **Step 6: コミットする**

```bash
git add MmdviewApp/mmdview/App/MainMenuBuilder.swift MmdviewApp/mmdview/Resources/Localizable.xcstrings
git commit -m "feat: View メニューに Toggle Sidebar を追加する

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 7: 手動スモークテスト

**Files:** なし（手動テスト）

- [ ] **Step 1: アプリをビルドして起動する**

Run: `cd MmdviewApp && swift build && .build/debug/mmdview`

- [ ] **Step 2: 以下を確認する**

1. `.mmd` ファイルを開く → ビューアが表示される（サイドバーは閉じた状態）
2. View > Toggle Sidebar（`Cmd+Opt+S`）→ サイドバーが開く
3. サイドバーに親ディレクトリの対応ファイルが一覧表示される
4. サイドバーのファイルをクリック → ビューア内容が切り替わる
5. ウィンドウタイトルが切り替わったファイル名に更新される
6. サイドバーの幅をドラッグでリサイズできる
7. 再度 `Cmd+Opt+S` → サイドバーが閉じる
8. ウィンドウを閉じて再度開く → 正常に動作する

- [ ] **Step 3: 問題があれば修正し、全テストが通ることを確認してコミットする**
