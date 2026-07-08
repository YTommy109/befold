# G1: ウィンドウ/ファイル操作の基本動作改善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!-- derived-from ../specs/2026-07-08-g1-window-file-basics-design.md -->

**Goal:** ファイルを開いた際にウィンドウがアクティブにならない不具合を直し、
cmd+o の初期ディレクトリをウィンドウ単位で記憶し、サイドバーのパスコピーを
相対パスにする。

**Architecture:** 3つの独立した小さな変更。#1 はウィンドウオープンの単一箇所
(`ViewerWindowManager.openViewer`) への1行追加、#2/#6 はそれぞれ新規の純粋関数
(`OpenPanelDirectoryResolver` / `PathRelativizer`) を切り出してユニットテストし、
既存コードから呼び出す。

**Tech Stack:** Swift 6, AppKit, Swift Testing (`befoldTests/`)

## Global Constraints

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- テストは Swift Testing フレームワーク（`@Test` / `#expect`）を使う
- WebView/GUI 層（実ウィンドウのアクティブ化・`NSOpenPanel` の実表示）は
  自動テスト対象外。手動確認手順をタスク内に明記する
- コミットメッセージは Conventional Commits + 日本語（例: `fix: ...する`）

---

### Task 1: ファイルを開いた時にウィンドウをアクティブにする

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowManager.swift:20-44`

**Interfaces:**
- Consumes: なし（既存の `openViewer(for:forceSidebarVisible:)` を修正するのみ）
- Produces: なし（振る舞いの修正のみ、公開シグネチャは不変）

- [ ] **Step 1: 現状のコードを確認する**

```swift
func openViewer(for url: URL, forceSidebarVisible: Bool = false) {
    guard FileManager.default.fileExists(atPath: url.path) else {
        FileNotFoundUI.present(url: url, over: nil)
        return
    }

    let key = url.normalizedPathKey
    if let existing = controllers[key] {
        existing.window?.makeKeyAndOrderFront(nil)
        return
    }

    let controller = ViewerWindowController(
        fileURL: url,
        zoomStore: zoomStore,
        forceSidebarVisible: forceSidebarVisible
    )
    controllers[key] = controller
    bindCallbacks(for: controller, key: key, url: url)
    controller.showWindow(nil)
    sessionStore.noteOpened(url)
    recentDocumentsStore.noteOpened(url)
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
}
```

- [ ] **Step 2: `NSApp.activate()` を両分岐に追加する**

```swift
func openViewer(for url: URL, forceSidebarVisible: Bool = false) {
    guard FileManager.default.fileExists(atPath: url.path) else {
        FileNotFoundUI.present(url: url, over: nil)
        return
    }

    let key = url.normalizedPathKey
    if let existing = controllers[key] {
        NSApp.activate()
        existing.window?.makeKeyAndOrderFront(nil)
        return
    }

    let controller = ViewerWindowController(
        fileURL: url,
        zoomStore: zoomStore,
        forceSidebarVisible: forceSidebarVisible
    )
    controllers[key] = controller
    bindCallbacks(for: controller, key: key, url: url)
    NSApp.activate()
    controller.showWindow(nil)
    sessionStore.noteOpened(url)
    recentDocumentsStore.noteOpened(url)
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
}
```

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功（警告・エラーなし）

- [ ] **Step 4: 手動で動作確認する（自動テスト対象外）**

1. befold と別のアプリ（例: Finder）を両方起動し、別アプリを前面にする
2. ターミナルまたは Finder のダブルクリックで befold にファイルを開かせる
   （`open -a befold path/to/file.mmd` など）
3. befold のウィンドウが最前面に来てアクティブになることを確認する
4. befold が既に同じファイルを開いている状態で再度開いた場合も、既存
   ウィンドウが前面化することを確認する

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/ViewerWindowManager.swift
git commit -m "fix: ファイルを開いた時にウィンドウをアクティブにする"
```

---

### Task 2: cmd+o のディレクトリをウィンドウ単位で記憶する純粋ロジックを追加する

**Files:**
- Create: `BefoldApp/befold/App/OpenPanelDirectoryResolver.swift`
- Test: `BefoldApp/befoldTests/OpenPanelDirectoryResolverTests.swift`

**Interfaces:**
- Produces: `OpenPanelDirectoryResolver.resolve(lastOpenDirectory: URL?, homeDirectory: URL) -> URL`
  （Task 3 がこの関数を呼び出す）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// BefoldApp/befoldTests/OpenPanelDirectoryResolverTests.swift
@testable import befold
import Foundation
import Testing

@Suite
struct OpenPanelDirectoryResolverTests {
    @Test("記憶されたディレクトリがあればそれを返す")
    func returnsLastOpenDirectoryWhenPresent() {
        let last = URL(fileURLWithPath: "/Users/tester/Documents")
        let home = URL(fileURLWithPath: "/Users/tester")

        let resolved = OpenPanelDirectoryResolver.resolve(
            lastOpenDirectory: last, homeDirectory: home
        )

        #expect(resolved == last)
    }

    @Test("記憶が無ければホームディレクトリを返す")
    func returnsHomeDirectoryWhenLastOpenDirectoryIsNil() {
        let home = URL(fileURLWithPath: "/Users/tester")

        let resolved = OpenPanelDirectoryResolver.resolve(
            lastOpenDirectory: nil, homeDirectory: home
        )

        #expect(resolved == home)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter OpenPanelDirectoryResolverTests`
Expected: FAIL（`OpenPanelDirectoryResolver` が存在しないためビルドエラー）

- [ ] **Step 3: 最小実装を書く**

```swift
// BefoldApp/befold/App/OpenPanelDirectoryResolver.swift
import Foundation

/// cmd+o のファイル選択パネルの初期ディレクトリを決める純粋ロジック。
/// ウィンドウごとに記憶された最後のディレクトリがあればそれを、
/// 無ければ（ウィンドウ未オープン含む）ホームディレクトリを使う。
enum OpenPanelDirectoryResolver {
    static func resolve(lastOpenDirectory: URL?, homeDirectory: URL) -> URL {
        lastOpenDirectory ?? homeDirectory
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter OpenPanelDirectoryResolverTests`
Expected: PASS（2 tests passed）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/OpenPanelDirectoryResolver.swift BefoldApp/befoldTests/OpenPanelDirectoryResolverTests.swift
git commit -m "feat: cmd+o の初期ディレクトリ解決ロジックを追加する"
```

---

### Task 3: ウィンドウにディレクトリ記憶を持たせ、showOpenPanel から使う

**Files:**
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:18-19`
- Modify: `BefoldApp/befold/App/AppDelegate.swift:127-136`

**Interfaces:**
- Consumes: `OpenPanelDirectoryResolver.resolve(lastOpenDirectory:homeDirectory:)`（Task 2）
- Produces: `ViewerWindowController.lastOpenDirectory: URL?`（今後の拡張で参照される可能性あり）

- [ ] **Step 1: `ViewerWindowController` にプロパティを追加する**

`BefoldApp/befold/App/ViewerWindowController.swift:18` 付近
（`private(set) var isSourceMode = false` の下）に追加:

```swift
    private(set) var isSourceMode = false
    /// この ウィンドウで最後に cmd+o のファイル選択パネルを開いたディレクトリ。
    /// ウィンドウ単位の記憶であり、永続化はしない。
    var lastOpenDirectory: URL?
    private(set) var fileURL: URL
```

- [ ] **Step 2: `showOpenPanel` を書き換える**

`BefoldApp/befold/App/AppDelegate.swift:126-136` を置き換える:

```swift
    /// ファイル選択パネルを表示し、選択されたファイルをビューアで開く。
    /// 初期ディレクトリはキーウィンドウが最後に記憶したディレクトリ、
    /// 無ければ（未オープン含む）ホームディレクトリを使う。
    @objc func showOpenPanel() {
        let controller = NSApp.keyWindow?.windowController as? ViewerWindowController
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.directoryURL = OpenPanelDirectoryResolver.resolve(
            lastOpenDirectory: controller?.lastOpenDirectory,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.openViewer(for: url)
            }
            if let first = panel.urls.first {
                controller?.lastOpenDirectory = first.deletingLastPathComponent()
            }
        }
    }
```

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功

- [ ] **Step 4: 手動で動作確認する（`NSOpenPanel` の実表示は自動テスト対象外）**

1. befold であるウィンドウを開き、cmd+o で別のディレクトリのファイルを選ぶ
2. 同じウィンドウで再度 cmd+o を押し、パネルの初期ディレクトリが直前に
   選んだファイルのディレクトリになっていることを確認する
3. 別の新規ウィンドウ（記憶が無い状態）で cmd+o を押すと、ホーム
   ディレクトリが初期表示されることを確認する

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befold/App/AppDelegate.swift
git commit -m "feat: cmd+o の初期ディレクトリをウィンドウ単位で記憶する"
```

---

### Task 4: パス相対化の純粋ロジックを追加する

**Files:**
- Create: `BefoldApp/befold/Viewer/PathRelativizer.swift`
- Test: `BefoldApp/befoldTests/PathRelativizerTests.swift`

**Interfaces:**
- Produces: `PathRelativizer.relativePath(of: URL, relativeTo base: URL) -> String`
  （Task 5 がこの関数を呼び出す）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// BefoldApp/befoldTests/PathRelativizerTests.swift
@testable import befold
import Foundation
import Testing

@Suite
struct PathRelativizerTests {
    @Test("base 直下のファイルはファイル名だけになる")
    func directChildReturnsFileName() {
        let base = URL(fileURLWithPath: "/Users/tester/project")
        let url = URL(fileURLWithPath: "/Users/tester/project/README.md")

        #expect(PathRelativizer.relativePath(of: url, relativeTo: base) == "README.md")
    }

    @Test("ネストしたファイルはサブパスになる")
    func nestedChildReturnsSubPath() {
        let base = URL(fileURLWithPath: "/Users/tester/project")
        let url = URL(fileURLWithPath: "/Users/tester/project/docs/spec.md")

        #expect(PathRelativizer.relativePath(of: url, relativeTo: base) == "docs/spec.md")
    }

    @Test("base の外にあるファイルは絶対パスのままにする")
    func outsideBaseFallsBackToAbsolutePath() {
        let base = URL(fileURLWithPath: "/Users/tester/project")
        let url = URL(fileURLWithPath: "/Users/other/file.md")

        #expect(PathRelativizer.relativePath(of: url, relativeTo: base) == "/Users/other/file.md")
    }

    @Test("base 自身を渡すと空文字列になる")
    func baseItselfReturnsEmptyString() {
        let base = URL(fileURLWithPath: "/Users/tester/project")

        #expect(PathRelativizer.relativePath(of: base, relativeTo: base) == "")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter PathRelativizerTests`
Expected: FAIL（`PathRelativizer` が存在しないためビルドエラー）

- [ ] **Step 3: 最小実装を書く**

```swift
// BefoldApp/befold/Viewer/PathRelativizer.swift
import Foundation

/// パスをコピーする際に絶対パスではなく相対パスにするための純粋ロジック。
enum PathRelativizer {
    /// `url` を `base` からの相対パス文字列にする。
    /// `url` が `base` の外にある場合は `url.path`（絶対パス）にフォールバックする。
    static func relativePath(of url: URL, relativeTo base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.starts(with: baseComponents) else {
            return url.path
        }
        return urlComponents.dropFirst(baseComponents.count).joined(separator: "/")
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter PathRelativizerTests`
Expected: PASS（4 tests passed）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Viewer/PathRelativizer.swift BefoldApp/befoldTests/PathRelativizerTests.swift
git commit -m "feat: パス相対化ロジックを追加する"
```

---

### Task 5: サイドバーのパスコピーを相対パスにする

**Files:**
- Modify: `BefoldApp/befold/Viewer/FileListView.swift:183-187`

**Interfaces:**
- Consumes: `PathRelativizer.relativePath(of:relativeTo:)`（Task 4）、
  `model.currentDirectory`（既存の `FileListModel` プロパティ）

- [ ] **Step 1: `copyPath` を書き換える**

`BefoldApp/befold/Viewer/FileListView.swift:183-187` を置き換える:

```swift
    private func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            PathRelativizer.relativePath(of: url, relativeTo: model.currentDirectory),
            forType: .string
        )
    }
```

- [ ] **Step 2: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功

- [ ] **Step 3: 全テストを実行する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS（新規4件を含む）

- [ ] **Step 4: 手動で動作確認する**

1. befold でフォルダーを開き、サイドバーのサブフォルダー内のファイルを
   右クリックして「パスをコピー」を選ぶ
2. ペーストして、現在ディレクトリからの相対パス（例: `docs/spec.md`）に
   なっていることを確認する

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/Viewer/FileListView.swift
git commit -m "fix: サイドバーのパスコピーを相対パスにする"
```
