# Folder Preview Listing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サイドバーでフォルダーを選択したときにプレビューエリアがフォルダー直下の一覧を表示するようにし、あわせてフォルダー移動時の「最初のファイルを自動的に開く」挙動を廃止する。

**Architecture:** `FileListModel.selection` / `currentDirectory` を単一の情報源として使う純粋関数 `PreviewTargetResolver` を新設し、`ViewerContentView` がそれを見て既存の `ViewerWebView` か新規 `FolderListingView`(SwiftUI `List`)のどちらを表示するか切り替える。フォルダー一覧の行表示は既存の `FileListView` の行表示を `FileListEntryRow` として抽出し、サイドバーとプレビューで共有する。

**Tech Stack:** Swift 6 / SwiftUI / AppKit(WKWebView)、Swift Testing(`@Test`/`#expect`)、既存の `DirectoryLister` / `FileListModel` / `SidebarNavigator`。

## Global Constraints

- サイドバーの隠しファイル表示(`HiddenFilesPreference.showHiddenFiles` 経由の `FileListModel.showHiddenFiles`)とソート順(`FileListModel.sortOrder`)を複製せずそのまま参照する。
- プレビュー内一覧はシングルクリック=選択のみ、ダブルクリックでファイルを開く/サブフォルダーへ移動する(サイドバーと同じ操作感)。
- パンくずリストなど新規ナビゲーションUIは追加しない。「..」(親ディレクトリ)行を戻る手段として使う。
- zip アーカイブ対応は本プランのスコープ外。
- GUI/WebView 層(SwiftUI の `body` レンダリングやジェスチャー)は自動テスト対象外(プロジェクトのテスト規約)。純粋ロジックは Swift Testing でユニットテストする。
- 各タスク完了後、アプリがビルドでき既存機能を壊さない状態を保つ(コミットごとに動作する状態を維持する)。

---

### Task 1: PreviewTargetResolver(プレビュー対象を決める純粋ロジック)

**Files:**
- Create: `BefoldApp/befold/Viewer/PreviewTargetResolver.swift`
- Test: `BefoldApp/befoldTests/PreviewTargetResolverTests.swift`

**Interfaces:**
- Produces: `enum PreviewTarget: Equatable { case file; case folder(URL) }` と `enum PreviewTargetResolver { static func resolve(selection: FileListEntry.ID?, entries: [FileListEntry], currentDirectory: URL) -> PreviewTarget }`。Task 4 でこの関数を `ViewerContentView` から呼ぶ。

- [ ] **Step 1: 失敗するテストを書く**

`BefoldApp/befoldTests/PreviewTargetResolverTests.swift` を新規作成する:

```swift
@testable import befold
import Foundation
import Testing

@Suite
struct PreviewTargetResolverTests {
    private let currentDirectory = URL(fileURLWithPath: "/tmp/PreviewTargetResolverTests")

    @Test("選択が nil のときは現在のディレクトリの一覧を対象にする")
    func nilSelectionResolvesToCurrentDirectory() {
        let target = PreviewTargetResolver.resolve(
            selection: nil, entries: [], currentDirectory: currentDirectory
        )
        #expect(target == .folder(currentDirectory))
    }

    @Test("選択がファイルのときはファイル表示を対象にする")
    func fileSelectionResolvesToFile() {
        let file = FileListEntry(url: currentDirectory.appendingPathComponent("a.mmd"), kind: .file)
        let target = PreviewTargetResolver.resolve(
            selection: file.id, entries: [file], currentDirectory: currentDirectory
        )
        #expect(target == .file)
    }

    @Test("選択がフォルダーのときはそのフォルダーの一覧を対象にする")
    func folderSelectionResolvesToThatFolder() {
        let folder = FileListEntry(url: currentDirectory.appendingPathComponent("sub"), kind: .folder)
        let target = PreviewTargetResolver.resolve(
            selection: folder.id, entries: [folder], currentDirectory: currentDirectory
        )
        #expect(target == .folder(folder.url))
    }

    @Test("選択が親ナビゲーション行のときはその行の URL の一覧を対象にする")
    func parentNavigationSelectionResolvesToParentFolder() {
        let parent = FileListEntry(url: currentDirectory.deletingLastPathComponent(), kind: .parentNavigation)
        let target = PreviewTargetResolver.resolve(
            selection: parent.id, entries: [parent], currentDirectory: currentDirectory
        )
        #expect(target == .folder(parent.url))
    }

    @Test("選択が一覧に存在しない(古い状態)ときは現在のディレクトリの一覧を対象にする")
    func staleSelectionFallsBackToCurrentDirectory() {
        let target = PreviewTargetResolver.resolve(
            selection: currentDirectory.appendingPathComponent("gone.mmd"),
            entries: [],
            currentDirectory: currentDirectory
        )
        #expect(target == .folder(currentDirectory))
    }
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `cd BefoldApp && swift test --filter PreviewTargetResolverTests`
Expected: FAIL(`PreviewTargetResolver`/`PreviewTarget` が存在せずビルドエラー)

- [ ] **Step 3: 最小実装を書く**

`BefoldApp/befold/Viewer/PreviewTargetResolver.swift` を新規作成する:

```swift
import Foundation

/// プレビューエリアが表示すべき対象。ファイルなら既存の ViewerWebView、
/// フォルダーなら FolderListingView(その URL 直下の一覧)を表示する。
enum PreviewTarget: Equatable {
    case file
    case folder(URL)
}

/// サイドバーの選択状態からプレビュー対象を決める純粋ロジック。
/// FileListModel/SidebarNavigator の状態をそのまま参照し、独自の状態を持たない。
enum PreviewTargetResolver {
    static func resolve(
        selection: FileListEntry.ID?,
        entries: [FileListEntry],
        currentDirectory: URL
    ) -> PreviewTarget {
        guard let selection,
              let entry = entries.first(where: { $0.id == selection })
        else {
            return .folder(currentDirectory)
        }
        return entry.kind == .file ? .file : .folder(entry.url)
    }
}
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `cd BefoldApp && swift test --filter PreviewTargetResolverTests`
Expected: PASS(5 tests)

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/Viewer/PreviewTargetResolver.swift befoldTests/PreviewTargetResolverTests.swift
git commit -m "feat: プレビュー対象を決める PreviewTargetResolver を追加する"
```

---

### Task 2: FileListEntryRow(サイドバー行表示の抽出)

**Files:**
- Create: `BefoldApp/befold/Viewer/FileListEntryRow.swift`
- Modify: `BefoldApp/befold/Viewer/FileListView.swift:55-132`

**Interfaces:**
- Produces: `struct FileListEntryRow: View { let entry: FileListEntry }`。Task 3 の `FolderListingView` がこれを使う。
- Consumes: `FileListEntry`(Task 0 で既存定義済み、変更なし)。

この抽出は見た目を一切変えないリファクタリング。GUI レンダリングのため自動テストはなく、ビルド成功と `/review-swift-code` 相当の目視確認で検証する。

- [ ] **Step 1: FileListEntryRow を新規作成する**

`BefoldApp/befold/Viewer/FileListEntryRow.swift` を新規作成する(内容は `FileListView.swift` の既存 `entryRow(_:)` の中身をそのまま移す):

```swift
import AppKit
import SwiftUI

/// サイドバー(FileListView)とプレビュー内フォルダー一覧(FolderListingView)が
/// 共有する行表示。ここを一箇所にすることで両者の見た目の基準を一致させる。
struct FileListEntryRow: View {
    let entry: FileListEntry

    var body: some View {
        switch entry.kind {
        case .parentNavigation:
            HStack {
                Label {
                    Text("..")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "arrow.up.doc")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .folder:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        case .file:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(entry.hasUnknownExtension ? .secondary : .primary)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
            }
        }
    }
}
```

- [ ] **Step 2: FileListView から呼び出すよう書き換える**

`BefoldApp/befold/Viewer/FileListView.swift` の `entryList` 内、`entryRow(entry)` の呼び出しを書き換える:

```swift
    private var entryList: some View {
        List(model.entries, selection: $model.selection) { entry in
            // 行インセットをゼロにして同等のパディングを行コンテンツ側へ移し、
            // contentShape が行の全幅を覆うようにする。インセット部分をダブル
            // クリックしたとき選択だけされて移動しない取りこぼしを防ぐ。
            FileListEntryRow(entry: entry)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets())
                .contentShape(.rect)
                .background(SidebarTableViewLocator { tableView in
                    model.sidebarTableView = tableView
                })
                .contextMenu { contextMenuItems(for: entry) }
                .simultaneousGesture(singleTapGesture(for: entry))
                .simultaneousGesture(doubleTapGesture(for: entry))
        }
```

続けて、同ファイル内の旧 `entryRow(_:)` 定義(`@ViewBuilder private func entryRow(_ entry: FileListEntry) -> some View { ... }` のブロック全体、`// MARK: - Context Menu` の直前まで)を削除する。

- [ ] **Step 3: ビルドして既存テストが通ることを確認する**

Run: `cd BefoldApp && swift build && swift test --filter FileListViewTests`
Expected: ビルド成功、既存の `FileListViewTests` が全て PASS(見た目のみの変更のため挙動テストに影響なし)

- [ ] **Step 4: コミット**

```bash
cd BefoldApp
git add befold/Viewer/FileListEntryRow.swift befold/Viewer/FileListView.swift
git commit -m "refactor: サイドバー行表示を FileListEntryRow として抽出する"
```

---

### Task 3: FolderListingView(新規のフォルダー一覧プレビュー)

**Files:**
- Create: `BefoldApp/befold/Viewer/FolderListingView.swift`

**Interfaces:**
- Consumes: `FileListEntryRow`(Task 2)、`DirectoryLister.listEntries(in:sortOrder:showHiddenFiles:)`(既存)、`SortOrder`(既存、`FileListEntry.swift` 定義)。
- Produces: `struct FolderListingView: View { let directory: URL; let sortOrder: SortOrder; let showHiddenFiles: Bool; let onSelectFile: (URL) -> Void; let onNavigateToFolder: (URL) -> Void }`。Task 4 で `ViewerContentView` がこれを使う。

この時点ではまだどこからも呼ばれない(未配線)。GUI のため自動テストはなく、ビルド成功で検証する。

- [ ] **Step 1: FolderListingView を新規作成する**

`BefoldApp/befold/Viewer/FolderListingView.swift` を新規作成する:

```swift
import BefoldKit
import SwiftUI

/// サイドバーでフォルダーが選択された際にプレビューエリアへ表示する、
/// そのフォルダー直下の一覧。WKWebView を使わず SwiftUI の List で完結させる。
/// 隠しファイル表示・並び順はサイドバー(FileListModel)の現在値をそのまま渡してもらい、
/// このビュー自身は独自の設定を持たない。
struct FolderListingView: View {
    let directory: URL
    let sortOrder: SortOrder
    let showHiddenFiles: Bool
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void

    /// このビュー内だけのハイライト選択。サイドバーの選択状態(FileListModel.selection)とは
    /// 同期しない。ダブルクリックで確定した操作(onSelectFile/onNavigateToFolder)だけが
    /// サイドバー側の状態を書き換える。
    @State private var localSelection: FileListEntry.ID?

    private var entries: [FileListEntry] {
        DirectoryLister.listEntries(in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles)
    }

    var body: some View {
        List(entries, selection: $localSelection) { entry in
            FileListEntryRow(entry: entry)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets())
                .contentShape(.rect)
                .simultaneousGesture(singleTapGesture(for: entry))
                .simultaneousGesture(doubleTapGesture(for: entry))
        }
        .overlay {
            if entries.allSatisfy({ $0.kind == .parentNavigation }) {
                ContentUnavailableView(
                    String(localized: "sidebar.empty", bundle: .l10n),
                    systemImage: "doc.questionmark",
                    description: Text(directory.lastPathComponent)
                )
                .allowsHitTesting(false)
            }
        }
        .id(directory)
    }

    /// シングルクリックはハイライトのみ(サイドバーと同じ操作感)。
    private func singleTapGesture(for entry: FileListEntry) -> some Gesture {
        TapGesture().onEnded {
            localSelection = entry.id
        }
    }

    /// ダブルクリックでファイルを開く/サブフォルダーへ移動する。
    private func doubleTapGesture(for entry: FileListEntry) -> some Gesture {
        TapGesture(count: 2).onEnded {
            switch entry.kind {
            case .file:
                onSelectFile(entry.url)
            case .folder, .parentNavigation:
                onNavigateToFolder(entry.url)
            }
        }
    }
}
```

`.id(directory)` は、表示先フォルダーが切り替わったときに `localSelection`(ハイライト)を前のフォルダーの選択のまま残さず、新しい一覧に対してリセットするためのもの。

- [ ] **Step 2: ビルドを確認する**

Run: `cd BefoldApp && swift build`
Expected: ビルド成功(未配線のため実行時の見た目は変わらない)

- [ ] **Step 3: コミット**

```bash
cd BefoldApp
git add befold/Viewer/FolderListingView.swift
git commit -m "feat: フォルダー一覧プレビュー FolderListingView を追加する"
```

---

### Task 4: ViewerContentView / ViewerWindowController への配線

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:182-224`

**Interfaces:**
- Consumes: `PreviewTargetResolver.resolve`(Task 1)、`FolderListingView`(Task 3)、既存の `FileListModel`。
- Produces: `ViewerContentView` の新しい初期化パラメータ `fileListModel: FileListModel`, `onSelectFile: (URL) -> Void`, `onNavigateToFolder: (URL) -> Void`(呼び出し元は `ViewerWindowController.makeSplitViewController()` のみ)。

GUI 配線のため自動テストはなく、ビルド成功と既存テストスイート全体の PASS、および手動確認(Task 6)で検証する。

- [ ] **Step 1: ViewerContentView を書き換える**

`BefoldApp/befold/Viewer/ViewerContentView.swift` を以下の内容に書き換える:

```swift
import BefoldKit
import SwiftUI

struct ViewerContentView: View {
    let store: ViewerStore
    let zoomStore: ZoomStore
    let scrollPositionStore: ScrollPositionStore
    let findOptionsPreference: FindOptionsPreference
    let fileListModel: FileListModel
    let onZoomChanged: @MainActor (Double) -> Void
    let onScrollPositionChanged: @MainActor (_ position: Double, _ mode: ViewerBridge.ViewMode) -> Void
    let onOpenReference: @MainActor (_ href: String, _ newWindow: Bool) -> Void
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void
    let webViewProxy: WebViewProxy

    /// 表示中ファイルの保存倍率。ファイル切替(store.filePath 変化)で再評価され、
    /// 切替先ファイルの倍率が ViewerWebView の coordinator へ渡る。
    /// これがないと初回ファイルの倍率がウィンドウ生存中ずっと固定されてしまう。
    private var currentZoom: Double {
        guard let url = store.filePath else { return ZoomStore.defaultZoom }
        return zoomStore.zoom(for: url)
    }

    private var currentScrollPosition: Double {
        guard let url = store.filePath else { return 0 }
        let mode: ViewerBridge.ViewMode = store.isSourceMode ? .source : .rendered
        return scrollPositionStore.scrollPosition(for: url, mode: mode)
    }

    /// サイドバーの選択状態から、プレビューエリアが表示すべき対象を決める。
    private var previewTarget: PreviewTarget {
        PreviewTargetResolver.resolve(
            selection: fileListModel.selection,
            entries: fileListModel.entries,
            currentDirectory: fileListModel.currentDirectory
        )
    }

    var body: some View {
        switch previewTarget {
        case .file:
            // ViewerWebView は常に生かしておき(ビュー同一性を維持)、非対応時は
            // 上に UnsupportedFileView を重ねる。テキスト↔バイナリの切替で WKWebView が
            // 破棄・再生成されて白フラッシュや stale な initialZoom が起きるのを防ぐ。
            ZStack {
                ViewerWebView(
                    content: store.content,
                    contentRevision: store.contentRevision,
                    fileType: store.fileType,
                    filePath: store.filePath,
                    isSourceMode: store.isSourceMode,
                    showLineNumbers: store.showLineNumbers,
                    isTruncated: store.isTruncated,
                    lineCount: store.displayedLineCount,
                    loadFailed: store.loadFailed,
                    initialZoom: currentZoom,
                    scrollPositionToRestore: currentScrollPosition,
                    onScrollPositionChanged: onScrollPositionChanged,
                    onZoomChanged: onZoomChanged,
                    onLoadMoreLines: {
                        await store.loadMoreLines()
                    },
                    onOpenReference: onOpenReference,
                    findOptionsPreference: findOptionsPreference,
                    webViewProxy: webViewProxy
                )
                .opacity(store.isRejected ? 0 : 1)

                if let reason = store.rejectReason {
                    UnsupportedFileView(fileURL: store.filePath, rejectReason: reason)
                } else if store.isLoading, store.content.isEmpty {
                    LoadingIndicatorView()
                }
            }
        case let .folder(url):
            FolderListingView(
                directory: url,
                sortOrder: fileListModel.sortOrder,
                showHiddenFiles: fileListModel.showHiddenFiles,
                onSelectFile: onSelectFile,
                onNavigateToFolder: onNavigateToFolder
            )
        }
    }
}
```

- [ ] **Step 2: ViewerWindowController の呼び出しを書き換える**

`BefoldApp/befold/App/ViewerWindowController.swift` の `makeSplitViewController()`(182-224行目)を以下に書き換える:

```swift
    /// サイドバー(ファイル一覧)とコンテンツ(WebView/フォルダー一覧)を並べる split view controller を組み立てる。
    private func makeSplitViewController() -> NSViewController {
        let onSelectFile: (URL) -> Void = { [weak self] url in self?.switchFile(to: url) }
        let onNavigateToFolder: (URL) -> Void = { [weak self] url in self?.navigateToFolder(url) }
        let contentView = ViewerContentView(
            store: store,
            zoomStore: zoomStore,
            scrollPositionStore: scrollPositionStore,
            findOptionsPreference: findOptionsPreference,
            fileListModel: fileListModel,
            // 現在の fileURL は rename で書き換わるため、旧値を捕捉せず self 経由で参照する
            onZoomChanged: { [weak self] zoom in
                guard let self else { return }
                zoomStore.setZoom(zoom, for: fileURL)
            },
            onScrollPositionChanged: { [weak self] position, mode in
                guard let self else { return }
                scrollPositionStore.setScrollPosition(position, for: fileURL, mode: mode)
            },
            onOpenReference: { [weak self] href, newWindow in
                self?.handleOpenReference(href: href, newWindow: newWindow)
            },
            onSelectFile: onSelectFile,
            onNavigateToFolder: onNavigateToFolder,
            webViewProxy: webViewProxy
        )
        let fileListView = FileListView(
            model: fileListModel,
            onSelect: onSelectFile,
            onNavigate: onNavigateToFolder,
            onSortOrderChanged: { [weak self] order in
                guard let self else { return }
                fileListModel.sortOrder = order
                sidebar.refreshFileList()
            },
            onOpenInNewWindow: { url in
                AppDelegate.shared?.openViewer(for: url)
            },
            onToggleHiddenFiles: { [weak self] in
                guard let self else { return }
                delegate?.viewerWindowDidToggleHiddenFiles(self)
            }
        )
        return ViewerSplitViewController(
            sidebar: fileListView,
            content: contentView,
            forceSidebarVisible: forceSidebarVisible
        )
    }
```

- [ ] **Step 3: ビルドとテストスイート全体を実行して既存機能が壊れていないことを確認する**

Run: `cd BefoldApp && swift build && swift test`
Expected: ビルド成功。既存の全テストが PASS(ファイル選択時は `previewTarget == .file` になり従来通り `ViewerWebView` が表示されるため、`ViewerWindowControllerTests`・`SidebarNavigatorIntegrationTests` を含め回帰がないはず)

- [ ] **Step 4: コミット**

```bash
cd BefoldApp
git add befold/Viewer/ViewerContentView.swift befold/App/ViewerWindowController.swift
git commit -m "feat: フォルダー選択時にプレビューエリアへ一覧を表示する"
```

---

### Task 5: navigateToFolder の自動オープンを廃止する

**Files:**
- Modify: `BefoldApp/befold/App/SidebarNavigator.swift:124-147`
- Modify: `BefoldApp/befoldTests/ViewerWindowControllerTests.swift:377-411`

**Interfaces:**
- Consumes: なし(既存 `SidebarNavigator` 内部の変更のみ)。
- Produces: `navigateToFolder(_:)` の外部シグネチャは変更しない。呼び出し後の `fileListModel.selection` が「上へ移動」以外では常に `nil` になる点が既存動作からの変更(Task 4 により、この結果プレビューエリアには新ディレクトリの一覧が表示される)。

- [ ] **Step 1: 既存の2テストを新しい期待値に書き換える(失敗させる)**

`BefoldApp/befoldTests/ViewerWindowControllerTests.swift` の `navigateToChildSelectsFirstFileSkippingFolders`(377-395行目)と `navigateToChildOpensFirstFile`(397-411行目)を、以下の2つに置き換える:

```swift
    @Test("子フォルダーへの移動では自動選択されない")
    func navigateToChildDoesNotAutoSelect() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let grandChild = subDir.appendingPathComponent("grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: grandChild, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = makeController(file: file)
        defer { controller.close() }

        controller.navigateToFolder(subDir)

        #expect(controller.fileListModel.selection == nil)
    }

    @Test("子フォルダーへの移動ではファイルが自動的に開かれない")
    func navigateToChildDoesNotAutoOpenFile() throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = makeController(file: file)
        defer { controller.close() }

        controller.navigateToFolder(subDir)

        #expect(controller.fileURL.lastPathComponent == "diagram.mmd")
    }
```

(`navigateToChildWithoutFilesClearsSelection` はそのまま変更不要。既に「ファイルの無いフォルダーへの移動で selection が nil になる」ことを検証しており、今回の変更後も成立する。)

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `cd BefoldApp && swift test --filter navigateToChildDoesNotAutoSelect`
Run: `cd BefoldApp && swift test --filter navigateToChildDoesNotAutoOpenFile`
Expected: 両方 FAIL(現状の実装はまだ最初のファイルを自動選択・自動オープンするため)

- [ ] **Step 3: SidebarNavigator.navigateToFolder を書き換える**

`BefoldApp/befold/App/SidebarNavigator.swift` の `navigateToFolder(_:)`(124-147行目)を以下に書き換える:

```swift
    /// サイドバーで別フォルダーへ移動する。ホームディレクトリ配下のみ許可する。
    /// 移動先に最初から自動的にファイルを開くことはしない(#folder-preview-listing)。
    /// 選択を空にすることで、プレビューエリアには新しいディレクトリの一覧が表示される
    /// (PreviewTargetResolver.resolve が selection == nil を currentDirectory の一覧として扱う)。
    func navigateToFolder(_ url: URL) {
        guard host != nil else { return }
        let target = url.standardizedFileURL
        guard DirectoryLister.isWithinHome(target) else { return }
        let previous = fileListModel.currentDirectory
        fileListModel.currentDirectory = url
        updateRootDirectory(with: target)
        let showHiddenFiles = syncShowHiddenFiles()
        fileListModel.entries = DirectoryLister.listEntries(
            in: url, sortOrder: fileListModel.sortOrder, showHiddenFiles: showHiddenFiles
        )
        let isGoingUp = target.normalizedPathKey == previous.deletingLastPathComponent()
            .normalizedPathKey
        if isGoingUp {
            fileListModel.selection = folderEntryURL(forKey: previous.normalizedPathKey)
        } else {
            fileListModel.selection = nil
        }
        recordHistory()
    }
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS(Task 4 までの変更と合わせて、フォルダー移動後は `FolderListingView` が表示される状態になる)

- [ ] **Step 5: コミット**

```bash
cd BefoldApp
git add befold/App/SidebarNavigator.swift befoldTests/ViewerWindowControllerTests.swift
git commit -m "fix: フォルダー移動時に最初のファイルを自動的に開かないようにする"
```

---

### Task 6: 手動確認

自動テスト対象外の GUI 挙動を、実アプリで確認する。

- [ ] **Step 1: アプリを起動する**

Run: `cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold`
起動後、`.mmd`/`.md` ファイルと複数階層のサブフォルダー・非対応ファイル(例: `.txt`)・隠しファイル(`.foo`)を含むテスト用フォルダーを開く。

- [ ] **Step 2: 確認項目**

- [ ] サイドバーでフォルダーをシングルクリックすると、プレビューエリアにそのフォルダー直下の一覧(フォルダー優先＋名前順)が表示される
- [ ] 一覧内の非対応ファイルはグレー表示され、選択はできる
- [ ] サイドバーの隠しファイル表示トグルを切り替えると、プレビュー内の一覧にも同じ隠しファイルが反映される
- [ ] プレビュー内一覧のファイル行をシングルクリックしても何も開かず、ダブルクリックで開く
- [ ] プレビュー内一覧のサブフォルダー行をダブルクリックすると、サイドバーの現在ディレクトリごと移動し、サイドバーのハイライトも追従する。移動後は最初のファイルが自動的に開かれず、新しいディレクトリの一覧が表示される
- [ ] 「..」行のダブルクリックで一つ上の階層へ戻れる
- [ ] 空フォルダーを選択すると空状態メッセージが表示される

- [ ] **Step 3: SwiftLint を実行する**

Run: `cd BefoldApp && swiftlint`
Expected: 新規・変更ファイルに違反なし
