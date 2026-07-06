# Folder Navigation Design

## Summary

ファイル一覧サイドバーにフォルダー表示とフォルダー間ナビゲーションを追加する。
キーボード操作（矢印キー・vim キー）による移動と、ファイル・フォルダー共通のコンテキストメニューを提供する。

## Requirements

- ファイル一覧にフォルダー（サブディレクトリ）を表示する
- デフォルトはフォルダーファーストソート、ヘッダーボタンでアルファベット混在に切り替え可能
- 最上位行に親フォルダーへの移動行を表示する
- ナビゲーション上限はホームディレクトリ（`~/`）
- キーボード操作: 上下移動（矢印 / j・k）、子フォルダーに入る（Return / 右矢印 / l）、親フォルダーに戻る（左矢印 / h / Backspace）
- コンテキストメニュー: コピー、新しいウィンドウで開く、パスをコピーする、Finder で開く

## Architecture

### 現在の構成

```
ViewerSplitViewController
  ├── Sidebar: NSHostingController(FileListView)
  │     └── FileListModel (files: [URL], selection: URL?)
  └── Content: NSHostingController(ViewerContentView)
```

### 変更後の構成

```
ViewerSplitViewController
  ├── Sidebar: NSHostingController(FileListView)
  │     └── FileListModel
  │           ├── currentDirectory: URL
  │           ├── entries: [FileListEntry]  (folders + files)
  │           ├── selection: FileListEntry.ID?
  │           └── sortOrder: SortOrder (.foldersFirst | .alphabetical)
  └── Content: NSHostingController(ViewerContentView)
```

## Data Model

### FileListEntry

```swift
struct FileListEntry: Identifiable, Hashable {
    enum Kind { case parentNavigation, folder, file }
    let id: URL
    let kind: Kind
    let url: URL
}
```

- `parentNavigation`: 最上位に表示する「..」行。`url` は親ディレクトリを指す
- `folder`: サブディレクトリ
- `file`: 対応ファイル（`FileType.allExtensions` でフィルタ）

### FileListModel の拡張

```swift
@MainActor @Observable
final class FileListModel {
    var currentDirectory: URL
    var entries: [FileListEntry]
    var selection: FileListEntry.ID?  // URL
    var sortOrder: SortOrder

    enum SortOrder { case foldersFirst, alphabetical }
}
```

## Changes to Existing Components

### DirectoryLister

現在の `listFiles(in:)` を拡張し、フォルダーも返す新メソッドを追加する。

```swift
enum DirectoryLister {
    static func listFiles(in directory: URL) -> [URL]  // 既存（互換性維持）
    static func listEntries(in directory: URL, sortOrder: FileListModel.SortOrder) -> [FileListEntry]  // 新規
}
```

`listEntries` の動作:
1. `FileManager.contentsOfDirectory` で隠しファイルを除外して取得
2. ディレクトリとファイル（`FileType.allExtensions` フィルタ）を分離
3. `sortOrder` に応じてソート:
   - `.foldersFirst`: フォルダー群（名前順）→ ファイル群（名前順）
   - `.alphabetical`: フォルダー・ファイル混在で名前順
4. 先頭に `parentNavigation` エントリを挿入（現在のディレクトリがホームディレクトリでない場合のみ）

### FileListView

<!-- constrained-by #data-model -->

SwiftUI `List` を `FileListEntry` ベースに変更する。

- 各行の表示:
  - `parentNavigation`: フォルダーアイコン + 「..」テキスト
  - `folder`: フォルダーアイコン + フォルダー名 + シェブロン（`>`）
  - `file`: ファイルアイコン（`NSWorkspace.shared.icon`）+ ファイル名
- コンテキストメニュー（`.contextMenu`）を全行に付与
- ヘッダー領域にソート切り替えボタンを配置

### キーボード操作

SwiftUI の `List` 標準の上下矢印選択に加え、`.onKeyPress` で以下を処理:

| キー | 動作 |
|------|------|
| `j` | 次の項目を選択 |
| `k` | 前の項目を選択 |
| Return / 右矢印 / `l` | 選択がフォルダー → `navigateToFolder()`、ファイル → `onSelect()` |
| 左矢印 / `h` / Backspace (Delete) | 親フォルダーへ移動 |

- 上下矢印は `List` 標準動作に任せる（選択変更のみ、フォルダーに入る動作はしない）
- Return でファイルを選択した場合は `onSelect()` を呼ぶ（既存の選択動作と同じ）

### ViewerWindowController

- `refreshFileList()` を `DirectoryLister.listEntries` に切り替える
- フォルダーナビゲーション時:
  - `fileListModel.currentDirectory` を更新
  - `listEntries` で新ディレクトリの内容を取得
  - ファイル選択は解除（フォルダー移動のみ）
- 新メソッド `navigateToFolder(_ url: URL)`:
  - `currentDirectory` を更新し、エントリ一覧をリフレッシュ
  - ホームディレクトリ（`~`）より上への移動は無視する

### コンテキストメニュー

ファイル・フォルダー共通で以下の4項目を表示:

| メニュー項目 | ファイルの動作 | フォルダーの動作 |
|-------------|---------------|-----------------|
| コピー | `NSPasteboard` にファイル参照をコピー | `NSPasteboard` にフォルダー参照をコピー |
| 新しいウィンドウで開く | 新しいウィンドウでファイルを開く | フォルダー内の最初の対応ファイルを新しいウィンドウで開く |
| パスをコピーする | フルパスのテキストをクリップボードにコピー | フルパスのテキストをクリップボードにコピー |
| Finder で開く | `NSWorkspace.shared.activateFileViewerSelecting([url])` | 同左 |

- `parentNavigation` 行にはコンテキストメニューを表示しない
- フォルダーの「新しいウィンドウで開く」: 対応ファイルがない場合はメニュー項目をグレーアウト

### ソート切り替え

- サイドバーヘッダーにトグルボタンを配置
- SF Symbols アイコン: `folder` / `textformat.abc`（またはフォルダーファースト/アルファベット混在を示すアイコン）
- 切り替え時にエントリ一覧を再ソートする
- 設定はウィンドウ単位（永続化しない、デフォルトはフォルダーファースト）

## Data Flow

```
1. ユーザーがファイルを開く
   → ViewerWindowController.init(fileURL:)
   → DirectoryLister.listEntries(in: parentDir, sortOrder: .foldersFirst)
   → FileListModel.entries に一覧をセット（親ナビ + フォルダー + ファイル）

2. サイドバーでファイルをクリック / Return
   → FileListView の選択が変化
   → onSelect(url) → ViewerWindowController.switchFile(to:)
   → 既存のファイル切り替えフロー

3. サイドバーでフォルダーをクリック / Return / 右矢印 / l
   → onNavigate(url) → ViewerWindowController.navigateToFolder(url)
   → FileListModel.currentDirectory を更新
   → listEntries で新ディレクトリをスキャン
   → FileListModel.entries を差し替え、選択を解除

4. 親フォルダーへ移動（「..」行クリック / 左矢印 / h / Backspace）
   → navigateToFolder(currentDirectory.deletingLastPathComponent())
   → ホームディレクトリチェック（~/より上なら無視）

5. ソート切り替え
   → FileListModel.sortOrder を変更
   → listEntries で再ソート → entries を差し替え
```

## Edge Cases

- ホームディレクトリにいるとき: `parentNavigation` 行を表示しない
- フォルダーに対応ファイルもサブフォルダーもない: 空状態メッセージ（「対応ファイルがありません」）を表示
- フォルダーの「新しいウィンドウで開く」で対応ファイルがない: メニュー項目をグレーアウト
- ディレクトリが削除された場合: `listEntries` が空を返し、空状態表示になる

## Out of Scope

- ファイル監視によるリスト自動更新（既存の `windowDidBecomeKey` でのリフレッシュを継続）
- ソート設定の永続化
- ドラッグ & ドロップ
- ファイル検索 / フィルタ
- 複数選択
