# File List Sidebar Design

## Summary

ウィンドウの左側にリサイズ・開閉可能なサイドバーを追加し、
開いたファイルの親ディレクトリ内の対応ファイル一覧を表示する。
サイドバーでファイルをクリックすると同じウィンドウ内で表示を切り替える。

## Requirements

- 開いたファイルの親ディレクトリ直下の対応ファイル（`FileType.allExtensions`）をフラットに一覧表示する
- サイドバーの幅はドラッグでリサイズ可能（最小 150pt / 最大 300pt / デフォルト 200pt）
- サイドバーの開閉トグル（View メニュー + `Cmd+B`）
- サイドバーの初期状態は閉じた状態（既存の単一ファイル体験を維持）
- ファイルクリックで同じウィンドウ内の表示を切り替える（`ViewerStore.openFile()`）
- 切り替え時にウィンドウのタイトル・`representedURL`・管理辞書キーも更新する

## Architecture

```
ViewerWindowController
  └── NSSplitViewController (contentViewController)
        ├── NSSplitViewItem(.sidebar)
        │     └── NSHostingController(FileListView)
        └── NSSplitViewItem(.contentList)
              └── NSHostingController(ViewerContentView)  ← existing
```

`NSSplitViewController` を使うことで macOS 標準のサイドバー挙動
（`toggleSidebar:` アクション・アニメーション付き開閉・幅の自動永続化）を得る。

## New Components

### `Viewer/DirectoryLister.swift`

指定ディレクトリ内の対応ファイル一覧を取得するユーティリティ。

- `static func listFiles(in directory: URL) -> [URL]`
- `FileManager.contentsOfDirectory` でフラットに取得
- `FileType.allExtensions` でフィルタ
- ファイル名でソート（`localizedStandardCompare`）
- 隠しファイル（`.` prefix）を除外

### `Viewer/FileListView.swift`

SwiftUI `List` でファイル名を表示する View。

- `@Binding var selectedFile: URL?` — 選択中のファイル
- `let files: [URL]` — 表示するファイル一覧
- 各行: ファイルアイコン（`NSWorkspace.shared.icon(forFile:)`）+ ファイル名
- 選択変更時にコールバックで `ViewerStore.openFile()` を呼ぶ

### `App/ViewerSplitViewController.swift`

`NSSplitViewController` サブクラス。

- sidebar（`NSSplitViewItem.Behavior.sidebar`）+ content の 2 ペイン
- sidebar に `NSHostingController(FileListView)` をホスト
- content に `NSHostingController(ViewerContentView)` をホスト
- `NSSplitView.autosaveName` でサイドバー幅を永続化
- 初期状態: サイドバーを折りたたんだ状態

## Changes to Existing Files

### `ViewerWindowController.swift`

- `init(fileURL:zoomStore:)`:
  - `NSWindow.contentView = NSHostingView(...)` を廃止
  - `NSWindow.contentViewController = ViewerSplitViewController(...)` に変更
- 新規メソッド `switchFile(to:)`:
  - `store.openFile(newURL)` を呼ぶ
  - `fileURL` プロパティを更新
  - ウィンドウの `title` / `representedURL` を更新
  - `frameAutosaveName` を新パスに移行
  - `zoomStore` のズーム倍率を新ファイルのものに適用
- 新規コールバック `onSwitchFile: ((_ old: URL, _ new: URL) -> Void)?`:
  - rename（ディスク上の移動）とは意味が異なるため専用のコールバックを追加
  - `ViewerWindowManager` が辞書キーの付け替えとセッション記録の更新に使用

### `MainMenuBuilder.swift`

- View メニューに「Toggle Sidebar」項目を追加
- action: `#selector(NSSplitViewController.toggleSidebar(_:))`
- キーボードショートカット: `Cmd+B`

### `ViewerWindowManager.swift`

- `bindCallbacks` に `onSwitchFile` のハンドリングを追加
  - 旧キーを辞書から除去し、新キーでコントローラを再登録
  - `sessionStore.noteClosed(oldURL)` + `sessionStore.noteOpened(newURL)`
  - `recentDocumentsStore.noteOpened(newURL)`

## Data Flow

```
1. ユーザーがファイルを開く
   → ViewerWindowController.init(fileURL:)
   → DirectoryLister.listFiles(in: fileURL.parentDirectory)
   → FileListView に一覧を渡す（選択中 = 開いたファイル）

2. サイドバーでファイルをクリック
   → FileListView の選択が変化
   → ViewerWindowController.switchFile(to: newURL)
   → ViewerStore.openFile(newURL)
   → WebView が新ファイルを表示
   → ウィンドウタイトル・representedURL を更新
   → onSwitchFile コールバック経由で ViewerWindowManager へ通知
   → 辞書キー付け替え + セッション記録更新
```

## Out of Scope

- ディレクトリを直接開くメニュー項目
- Finder 右クリック連携（Open With mmdview）
- ディレクトリアイコンの D&D
- サブディレクトリの再帰表示
- ファイル監視によるリスト自動更新（FS Events）
