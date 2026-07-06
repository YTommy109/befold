# Folder Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ファイル一覧サイドバーにフォルダー表示・ナビゲーション・コンテキストメニュー・キーボード操作を追加する

**Architecture:** `DirectoryLister` にフォルダー込みの `listEntries` メソッドを追加し、`FileListModel` を `FileListEntry` ベースに拡張する。`FileListView` でフォルダー行・親ナビ行・コンテキストメニュー・キーボード操作を実装し、`ViewerWindowController` に `navigateToFolder` を追加してフォルダー間移動を実現する。

**Tech Stack:** Swift 6 / SwiftUI / AppKit / Swift Testing

## Global Constraints

- macOS 14+
- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- テスト関数名は英語 camelCase、日本語の説明は `@Test("...")` の表示名で付ける
- Conventional Commits + 日本語

---

### Task 1: FileListEntry + FileType.allExtensions + DirectoryLister.listEntries

**Files:**
- Create: `BefoldApp/befold/Viewer/FileListEntry.swift`
- Modify: `BefoldApp/befold/Viewer/FileType.swift:59` (after `pdfExtensions`)
- Modify: `BefoldApp/befold/Viewer/DirectoryLister.swift`
- Test: `BefoldApp/befoldTests/DirectoryListerTests.swift`

**Interfaces:**
- Consumes: `FileType.allExtensions` (added in this task)
- Produces:
  - `FileListEntry` — `struct FileListEntry: Identifiable, Hashable, Sendable` with `url: URL`, `kind: Kind` (`.parentNavigation | .folder | .file`), `id: URL`
  - `SortOrder` — `enum SortOrder: Sendable { case foldersFirst, alphabetical }`
  - `DirectoryLister.listEntries(in:sortOrder:)` — `static func listEntries(in directory: URL, sortOrder: SortOrder) -> [FileListEntry]`
  - `FileType.allExtensions` — `static var allExtensions: Set<String>`

- [ ] **Step 1: テストファイルに listEntries のテストを書く**

`BefoldApp/befoldTests/DirectoryListerTests.swift` の末尾に以下のテストを追加する:

```swift
@Test("listEntries はフォルダーと対応ファイルを返し、非対応ファイルを除外する")
func listEntriesReturnsFoldersAndSupportedFiles() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    try FileManager.default.createDirectory(
        at: tmp.url.appendingPathComponent("subdir"),
        withIntermediateDirectories: true
    )
    _ = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
    _ = try tmp.file(named: "unknown.xyz", contents: "skip me")

    let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)

    let kinds = entries.map(\.kind)
    let names = entries.map(\.url.lastPathComponent)
    #expect(kinds.first == .parentNavigation)
    #expect(names.contains("subdir"))
    #expect(names.contains("diagram.mmd"))
    #expect(!names.contains("unknown.xyz"))
}

@Test("foldersFirst ソートではフォルダーがファイルより先に並ぶ")
func listEntriesFoldersFirstSort() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    try FileManager.default.createDirectory(
        at: tmp.url.appendingPathComponent("zebra"),
        withIntermediateDirectories: true
    )
    _ = try tmp.file(named: "alpha.mmd", contents: "")

    let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)
    let nonParent = entries.filter { $0.kind != .parentNavigation }

    #expect(nonParent[0].kind == .folder)
    #expect(nonParent[0].url.lastPathComponent == "zebra")
    #expect(nonParent[1].kind == .file)
    #expect(nonParent[1].url.lastPathComponent == "alpha.mmd")
}

@Test("alphabetical ソートではフォルダーとファイルが名前順で混在する")
func listEntriesAlphabeticalSort() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    try FileManager.default.createDirectory(
        at: tmp.url.appendingPathComponent("beta"),
        withIntermediateDirectories: true
    )
    _ = try tmp.file(named: "alpha.mmd", contents: "")

    let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .alphabetical)
    let nonParent = entries.filter { $0.kind != .parentNavigation }

    #expect(nonParent[0].url.lastPathComponent == "alpha.mmd")
    #expect(nonParent[1].url.lastPathComponent == "beta")
}

@Test("ホームディレクトリでは parentNavigation が含まれない")
func listEntriesNoParentAtHome() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let entries = DirectoryLister.listEntries(in: home, sortOrder: .foldersFirst)

    #expect(!entries.contains { $0.kind == .parentNavigation })
}

@Test("ホームディレクトリ以外では parentNavigation が先頭に含まれる")
func listEntriesHasParentBelowHome() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }

    let entries = DirectoryLister.listEntries(in: tmp.url, sortOrder: .foldersFirst)

    #expect(entries.first?.kind == .parentNavigation)
    #expect(entries.first?.url == tmp.url.deletingLastPathComponent())
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter DirectoryListerTests 2>&1 | tail -20`
Expected: コンパイルエラー（`FileListEntry`, `SortOrder`, `listEntries` が未定義）

- [ ] **Step 3: FileType.allExtensions を追加する**

`BefoldApp/befold/Viewer/FileType.swift` の 59 行目（`static let pdfExtensions = ["pdf"]`）の直後に追加:

```swift
static let allExtensions: Set<String> = Set(
    mermaidExtensions + markdownExtensions + svgExtensions + htmlExtensions
    + csvExtensions + tsvExtensions + codeExtensions
    + Array(imageExtensionMimeTypes.keys) + pdfExtensions
)
```

- [ ] **Step 4: FileListEntry.swift を作成する**

`BefoldApp/befold/Viewer/FileListEntry.swift` を新規作成:

```swift
import Foundation

enum SortOrder: Sendable {
    case foldersFirst
    case alphabetical
}

struct FileListEntry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable, Hashable {
        case parentNavigation
        case folder
        case file
    }

    let url: URL
    let kind: Kind

    var id: URL { url }
}
```

- [ ] **Step 5: DirectoryLister.listEntries を実装する**

`BefoldApp/befold/Viewer/DirectoryLister.swift` に `listEntries` メソッドを追加する。既存の `listFiles` はそのまま残す:

```swift
static func listEntries(in directory: URL, sortOrder: SortOrder) -> [FileListEntry] {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    let supportedExtensions = FileType.allExtensions
    var folders: [URL] = []
    var files: [URL] = []

    for url in contents {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            folders.append(url)
        } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
            files.append(url)
        }
    }

    let nameSort: (URL, URL) -> Bool = {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
    folders.sort(by: nameSort)
    files.sort(by: nameSort)

    var entries: [FileListEntry] = []

    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    let dir = directory.standardizedFileURL
    if dir != home {
        entries.append(FileListEntry(url: directory.deletingLastPathComponent(), kind: .parentNavigation))
    }

    switch sortOrder {
    case .foldersFirst:
        entries += folders.map { FileListEntry(url: $0, kind: .folder) }
        entries += files.map { FileListEntry(url: $0, kind: .file) }
    case .alphabetical:
        var mixed = folders.map { FileListEntry(url: $0, kind: .folder) }
            + files.map { FileListEntry(url: $0, kind: .file) }
        mixed.sort(by: { nameSort($0.url, $1.url) })
        entries += mixed
    }

    return entries
}
```

- [ ] **Step 6: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter DirectoryListerTests 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 7: コミットする**

```bash
git add BefoldApp/befold/Viewer/FileListEntry.swift BefoldApp/befold/Viewer/FileType.swift BefoldApp/befold/Viewer/DirectoryLister.swift BefoldApp/befoldTests/DirectoryListerTests.swift
git commit -m "feat: DirectoryLister.listEntries でフォルダーと対応ファイルを返す"
```

---

### Task 2: FileListModel 拡張 + ViewerWindowController 統合

**Files:**
- Modify: `BefoldApp/befold/Viewer/FileListView.swift:1-16` (FileListModel class)
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift`

**Interfaces:**
- Consumes: `FileListEntry`, `SortOrder`, `DirectoryLister.listEntries(in:sortOrder:)` (Task 1)
- Produces:
  - `FileListModel.currentDirectory: URL`, `.entries: [FileListEntry]`, `.sortOrder: SortOrder`
  - `ViewerWindowController.navigateToFolder(_:)` — `func navigateToFolder(_ url: URL)`

- [ ] **Step 1: FileListModel を拡張する**

`BefoldApp/befold/Viewer/FileListView.swift` の `FileListModel` クラス（8-16 行目）を以下に置き換える:

```swift
@MainActor
@Observable
final class FileListModel {
    var currentDirectory: URL
    var entries: [FileListEntry]
    var selection: FileListEntry.ID?
    var sortOrder: SortOrder

    init(currentDirectory: URL, entries: [FileListEntry], selection: FileListEntry.ID?) {
        self.currentDirectory = currentDirectory
        self.entries = entries
        self.selection = selection
        self.sortOrder = .foldersFirst
    }
}
```

- [ ] **Step 2: ViewerWindowController の初期化を更新する**

`BefoldApp/befold/App/ViewerWindowController.swift` の init 内（42-45 行目）を以下に置き換える:

```swift
let parentDir = fileURL.deletingLastPathComponent()
let entries = DirectoryLister.listEntries(in: parentDir, sortOrder: .foldersFirst)
fileListModel = FileListModel(
    currentDirectory: parentDir,
    entries: entries,
    selection: fileURL
)
```

- [ ] **Step 3: refreshFileList を listEntries ベースに更新する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `refreshFileList()`（236-243 行目）を以下に置き換える:

```swift
private func refreshFileList() {
    let entries = DirectoryLister.listEntries(
        in: fileListModel.currentDirectory,
        sortOrder: fileListModel.sortOrder
    )
    fileListModel.entries = entries
    if fileListModel.selection != fileURL {
        fileListModel.selection = fileURL
    }
}
```

- [ ] **Step 4: switchFile の参照を更新する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `switchFile(to:)`（210-213 行目）を以下に置き換える:

```swift
if newURL.deletingLastPathComponent() != oldURL.deletingLastPathComponent() {
    fileListModel.currentDirectory = newURL.deletingLastPathComponent()
    refreshFileList()
} else {
    fileListModel.selection = newURL
}
```

- [ ] **Step 5: listEntry(for:in:) を削除する**

`BefoldApp/befold/App/ViewerWindowController.swift` から `listEntry(for:in:)` メソッド（248-251 行目）を削除する。もう使われていない。

- [ ] **Step 6: navigateToFolder を追加する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `refreshFileList()` の直後に追加する:

```swift
func navigateToFolder(_ url: URL) {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    let target = url.standardizedFileURL
    guard target == home || target.path.hasPrefix(home.path + "/") else { return }
    fileListModel.currentDirectory = url
    fileListModel.entries = DirectoryLister.listEntries(in: url, sortOrder: fileListModel.sortOrder)
    fileListModel.selection = nil
}
```

- [ ] **Step 7: FileListView の初期化を一時的に修正する**

`BefoldApp/befold/Viewer/FileListView.swift` の `FileListView` 本体（18-40 行目）を一時的に以下に置き換える。Task 3 で完全版に置き換えるが、ビルドを通すために最低限の対応を入れる:

```swift
struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void

    var body: some View {
        List(model.entries, selection: $model.selection) { entry in
            Label {
                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        }
        .onChange(of: model.selection) { _, newValue in
            if let url = newValue,
               model.entries.first(where: { $0.id == url })?.kind == .file {
                onSelect(url)
            }
        }
    }
}
```

- [ ] **Step 8: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 9: 既存テストが通ることを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 10: コミットする**

```bash
git add BefoldApp/befold/Viewer/FileListView.swift BefoldApp/befold/App/ViewerWindowController.swift
git commit -m "feat: FileListModel をフォルダー対応に拡張し navigateToFolder を追加する"
```

---

### Task 3: FileListView UI（フォルダー行・ソート切替・コンテキストメニュー・キーボード操作）

**Files:**
- Modify: `BefoldApp/befold/Viewer/FileListView.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:111-130` (makeSplitViewController)

**Interfaces:**
- Consumes: `FileListModel` (Task 2), `FileListEntry` / `SortOrder` (Task 1), `ViewerWindowController.navigateToFolder(_:)` (Task 2)
- Produces: 完成版 `FileListView`（フォルダー行・親ナビ・ソート・コンテキストメニュー・キーボード）

- [ ] **Step 1: FileListView を完全版に置き換える**

`BefoldApp/befold/Viewer/FileListView.swift` の `FileListView` struct 全体（`struct FileListView: View {` から閉じ `}` まで）を以下に置き換える:

```swift
struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void
    let onNavigate: (URL) -> Void
    let onSortOrderChanged: (SortOrder) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            entryList
        }
    }

    private var header: some View {
        HStack {
            Text(model.currentDirectory.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                let next: SortOrder = model.sortOrder == .foldersFirst ? .alphabetical : .foldersFirst
                onSortOrderChanged(next)
            } label: {
                Image(systemName: model.sortOrder == .foldersFirst
                      ? "folder.fill" : "textformat.abc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(model.sortOrder == .foldersFirst ? "アルファベット順" : "フォルダー優先")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var entryList: some View {
        Group {
            if model.entries.allSatisfy({ $0.kind == .parentNavigation }) {
                ContentUnavailableView(
                    "対応ファイルがありません",
                    systemImage: "doc.questionmark",
                    description: Text(model.currentDirectory.lastPathComponent)
                )
            } else {
                List(model.entries, selection: $model.selection) { entry in
                    entryRow(entry)
                        .contextMenu { contextMenuItems(for: entry) }
                }
                .onChange(of: model.selection) { _, newValue in
                    if let url = newValue,
                       model.entries.first(where: { $0.id == url })?.kind == .file {
                        onSelect(url)
                    }
                }
                .onKeyPress { keyPress in
                    handleKeyPress(keyPress)
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: FileListEntry) -> some View {
        switch entry.kind {
        case .parentNavigation:
            Label {
                Text("..")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "arrow.up.doc")
                    .foregroundStyle(.secondary)
            }
        case .folder:
            Label {
                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        case .file:
            Label {
                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for entry: FileListEntry) -> some View {
        if entry.kind != .parentNavigation {
            Button("コピー") { copyFileReference(entry.url) }
            openInNewWindowButton(for: entry)
            Button("パスをコピーする") { copyPath(entry.url) }
            Button("Finder で開く") { revealInFinder(entry.url) }
        }
    }

    @ViewBuilder
    private func openInNewWindowButton(for entry: FileListEntry) -> some View {
        if entry.kind == .folder {
            let firstFile = DirectoryLister.listEntries(in: entry.url, sortOrder: .foldersFirst)
                .first { $0.kind == .file }
            Button("新しいウィンドウで開く") {
                if let file = firstFile {
                    AppDelegate.shared?.openViewer(for: file.url)
                }
            }
            .disabled(firstFile == nil)
        } else {
            Button("新しいウィンドウで開く") {
                AppDelegate.shared?.openViewer(for: entry.url)
            }
        }
    }

    private func copyFileReference(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    private func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Keyboard Navigation

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case "j":
            return selectNext()
        case "k":
            return selectPrevious()
        case .return, .rightArrow, "l":
            return enterSelected()
        case .leftArrow, "h", .delete:
            return navigateToParent()
        default:
            return .ignored
        }
    }

    private func selectNext() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.entries.firstIndex(where: { $0.id == current }),
              index + 1 < model.entries.count else {
            if model.selection == nil, let first = model.entries.first {
                model.selection = first.id
                return .handled
            }
            return .ignored
        }
        model.selection = model.entries[index + 1].id
        return .handled
    }

    private func selectPrevious() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.entries.firstIndex(where: { $0.id == current }),
              index > 0 else {
            return .ignored
        }
        model.selection = model.entries[index - 1].id
        return .handled
    }

    private func enterSelected() -> KeyPress.Result {
        guard let current = model.selection,
              let entry = model.entries.first(where: { $0.id == current }) else {
            return .ignored
        }
        switch entry.kind {
        case .parentNavigation, .folder:
            onNavigate(entry.url)
            return .handled
        case .file:
            return .ignored
        }
    }

    private func navigateToParent() -> KeyPress.Result {
        if let parent = model.entries.first(where: { $0.kind == .parentNavigation }) {
            onNavigate(parent.url)
            return .handled
        }
        return .ignored
    }
}
```

- [ ] **Step 2: makeSplitViewController の FileListView 初期化を更新する**

`BefoldApp/befold/App/ViewerWindowController.swift` の `makeSplitViewController()` 内（125-129 行目）の `FileListView` 初期化を以下に置き換える:

```swift
let fileListView = FileListView(
    model: fileListModel,
    onSelect: { [weak self] url in self?.switchFile(to: url) },
    onNavigate: { [weak self] url in self?.navigateToFolder(url) },
    onSortOrderChanged: { [weak self] order in
        guard let self else { return }
        fileListModel.sortOrder = order
        refreshFileList()
    }
)
```

- [ ] **Step 3: ビルドが通ることを確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: Build complete!

- [ ] **Step 4: 全テストが通ることを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 5: コミットする**

```bash
git add BefoldApp/befold/Viewer/FileListView.swift BefoldApp/befold/App/ViewerWindowController.swift
git commit -m "feat: FileListView にフォルダー行・コンテキストメニュー・キーボード操作を追加する"
```

- [ ] **Step 6: アプリをビルドして手動テストする**

Run: `/run` スキルでアプリを起動する

手動テスト項目:
1. `.mmd` ファイルを開き、サイドバー（⌘B）を表示する
2. フォルダーが一覧に表示されることを確認する
3. フォルダーファーストソート（フォルダーが上、ファイルが下）を確認する
4. ヘッダーのソートボタンをクリックしてアルファベット混在に切り替わることを確認する
5. 最上位に「..」行が表示されることを確認する
6. 「..」をクリックして親フォルダーに移動することを確認する
7. フォルダーをクリック → 選択のみ（移動しない）を確認する
8. フォルダー選択状態で Return → フォルダーに入ることを確認する
9. j / k で上下移動を確認する
10. l / 右矢印でフォルダーに入ることを確認する
11. h / 左矢印 / Backspace で親フォルダーに戻ることを確認する
12. ホームディレクトリで「..」が表示されないことを確認する
13. ホームディレクトリで左矢印 / h / Backspace が何もしないことを確認する
14. ファイルを右クリック → コンテキストメニュー 4 項目が表示されることを確認する
15. フォルダーを右クリック → コンテキストメニュー 4 項目が表示されることを確認する
16. 「..」行を右クリック → コンテキストメニューが表示されないことを確認する
17. 「コピー」→ Finder にペースト → ファイルがコピーされることを確認する
18. 「パスをコピーする」→ テキストエディタにペースト → パスが貼られることを確認する
19. 「Finder で開く」→ Finder が開くことを確認する
20. 「新しいウィンドウで開く」（ファイル）→ 新ウィンドウが開くことを確認する
21. 「新しいウィンドウで開く」（フォルダー）→ フォルダー内の最初のファイルが新ウィンドウで開くことを確認する
22. 対応ファイルがないフォルダーの「新しいウィンドウで開く」がグレーアウトしていることを確認する
23. 対応ファイルもサブフォルダーもないディレクトリに入ると「対応ファイルがありません」の空状態が表示されることを確認する
