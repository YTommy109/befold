# サイドバー ナビゲーション履歴（戻る/進む）設計

<!-- derived-from ./2026-07-06-folder-navigation-design.md -->
<!-- derived-from ./2026-07-05-file-list-sidebar-design.md -->

## 背景

befold のサイドバー（ファイル一覧）では、フォルダを移動したりファイルを選択して
表示を切り替えたりできる。しかし一度移動すると「直前に見ていた場所・ファイル」へ
戻る手段がなく、行き来のたびに手動でたどり直す必要がある。

Web ブラウザや Finder のような「戻る/進む」ナビゲーションをサイドバーに追加し、
ディレクトリ移動履歴とファイル参照履歴を辿れるようにする。

## 目的とスコープ

- サイドバー上部に「戻る」「進む」ボタンを追加する。
- ディレクトリ移動とファイル選択を **1本の統合された時系列履歴** として扱う
  （ブラウザ風）。
- Safari のように、戻る/進むボタンの **長押し + 右クリック** で履歴メニューを表示し、
  任意のエントリへ直接ジャンプできる。

### 非スコープ（YAGNI）

- 履歴のアプリ再起動をまたいだ永続化は行わない（メモリ内のみ・タブ生存中のみ）。
- ディレクトリ用とファイル用に履歴を分けることはしない（統合1本）。
- ウィンドウ間・タブ間での履歴共有はしない（タブごとに独立）。

## 決定事項

| 論点 | 決定 |
| ---- | ---- |
| 履歴モデル | 統合1本のスタック（ブラウザ風） |
| スコープ | タブ（`ViewerWindowController`）ごとに独立 |
| エントリ | `{directory, file?}` のスナップショット |
| 永続化 | しない（メモリ内のみ） |
| メニュー表示 | `ファイル名 — ディレクトリ名`（file が nil ならディレクトリ名のみ） |
| メニュー起動 | 戻る/進むボタンの長押し + 右クリック |

## アーキテクチャ

新規に純ロジックの型 `NavigationHistory` を1つ追加し、それを
`ViewerWindowController` がタブごとに1つ保持する。サイドバーへは
`FileListModel` を経由して履歴状態を渡す。

```
FileListView.header (SwiftUI, サイドバー上部)
  ├── 戻るボタン  / 進むボタン（.borderless、disabled 連動、長押し+右クリックで履歴メニュー）
  │        │ onBack / onForward / onJumpHistory(index)
  ▼        ▼
ViewerWindowController（タブごと）
  ├── history: NavigationHistory   ← 戻る/進むスタック本体（純ロジック）
  ├── switchFile(to:) / navigateToFolder(_:)  … ユーザー操作時に history.push
  ├── goBack() / goForward() / jumpHistory(to:) … applyEntry で適用（push しない）
  └── fileListModel（履歴状態を反映: canGoBack/canGoForward/backHistory/forwardHistory）
```

## コンポーネント

### 1. `NavigationHistory`（新規・純ロジック）

UI・AppKit 非依存で単体テスト可能な値の管理型。

```swift
struct HistoryEntry: Equatable {
    let directory: URL
    let file: URL?
}

@MainActor
final class NavigationHistory {
    private(set) var entries: [HistoryEntry] = []
    private(set) var currentIndex: Int = -1   // 空のとき -1

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < entries.count - 1 }

    /// 現在地以降の「進む」履歴を破棄して末尾追加し currentIndex を進める。
    /// 現在エントリと同一スナップショットなら何もしない（重複防止）。
    func push(_ entry: HistoryEntry)

    func goBack() -> HistoryEntry?      // currentIndex を1つ戻して返す
    func goForward() -> HistoryEntry?   // currentIndex を1つ進めて返す
    func jump(to index: Int) -> HistoryEntry?

    /// 戻るメニュー用（新しい順）。進むメニュー用（近い順）。
    func backEntries() -> [HistoryEntry]
    func forwardEntries() -> [HistoryEntry]

    /// rename/move 時に履歴内の該当 URL（directory/file とも）を更新する。
    func renameOccurred(from oldURL: URL, to newURL: URL)
}
```

- URL の同一判定・置換には既存の `url.normalizedPathKey`（`URL+PathKey.swift`）を
  用い、アプリ全体の一貫性に合わせる。

### 2. `ViewerWindowController`（既存・改修）

- `NavigationHistory` を1つ保持（タブごと）。
- `isNavigatingHistory: Bool` ガードを持つ。戻る/進む適用中は `push` を抑止。
- **新規ナビゲーション（push あり）**:
  - `switchFile(to:)`: ファイルを開いた後、
    `history.push(.init(directory: 現在ディレクトリ, file: newURL))`。
  - `navigateToFolder(_:)`: 一覧差し替え後、
    `history.push(.init(directory: url, file: 現在表示ファイル))`。
  - push 後に `refreshHistoryState()` で `fileListModel` の履歴プロパティを更新。
- **戻る/進む（push なし）**:
  - `goBack()` / `goForward()` / `jumpHistory(to:)` は `isNavigatingHistory = true`
    にして対象 `HistoryEntry` を `applyEntry(_:)` で適用し、最後にガード解除 +
    `refreshHistoryState()`。
  - `applyEntry(_:)`: ディレクトリを `DirectoryLister` で列挙し直して
    `fileListModel` を更新し、`file` があれば `store.openFile` で表示・サイドバー選択。
    既存の `navigateToFolder`/`switchFile` 内部処理を「push しない版」として共通化する。
- **rename**: `handleRename(to:)` 経路で `history.renameOccurred(from:to:)` を呼ぶ。

### 3. `FileListModel`（既存・改修）

サイドバーへ履歴状態を渡す口として以下を追加（コントローラが更新）:

```swift
var canGoBack: Bool = false
var canGoForward: Bool = false
var backHistory: [HistoryEntry] = []      // 戻るメニュー用（新しい順）
var forwardHistory: [HistoryEntry] = []   // 進むメニュー用（近い順）
```

### 4. `FileListView`（既存・改修）

- `header` に戻る/進むボタンを追加。既存ソートボタンと同じ
  `.buttonStyle(.borderless)` / `Image(systemName:)`（`chevron.backward` /
  `chevron.forward`）/ `.help(...)`（ローカライズ済みツールチップ）パターン。
- `model.canGoBack` / `model.canGoForward` に応じて `.disabled(...)`。
- **履歴メニュー**: 各ボタンに長押しジェスチャと `.contextMenu`（右クリック）を付け、
  `model.backHistory` / `model.forwardHistory` を項目化。ラベルは
  `ファイル名 — ディレクトリ名`（file が nil ならディレクトリ名のみ）。項目選択で
  `onJumpHistory(index)`。
- 新規コールバックを3つ追加: `onBack: () -> Void` / `onForward: () -> Void` /
  `onJumpHistory: (Int) -> Void`。`ViewerWindowController.makeSplitViewController()
  ` の配線箇所で接続する。

## データフロー

**新規ナビゲーション**

1. ファイル選択 → `onSelect` → `switchFile(to:)` → 表示切替 →
   `history.push({dir, file})` → `refreshHistoryState()`。
2. フォルダ移動 → `onNavigate` → `navigateToFolder(_:)` → 一覧差し替え →
   `history.push({dir, file})` → `refreshHistoryState()`。

**戻る/進む/ジャンプ**

1. ボタン/メニュー → `onBack` / `onForward` / `onJumpHistory(i)` →
   `goBack()` / `goForward()` / `jumpHistory(to: i)`。
2. `isNavigatingHistory = true` → `applyEntry(entry)`（ディレクトリ列挙 +
   `fileListModel` 更新 + `store.openFile` + 選択）→ `isNavigatingHistory = false`
   → `refreshHistoryState()`。

## エッジケース

- **存在しないファイル**: 適用時、削除済みなら既存の `ViewerStore.isDeleted`
  表示にそのまま委ねる。
- **存在しないディレクトリ**: 列挙が空になっても落ちないようガードする。メニューには
  一旦そのまま表示（過度に複雑化しない）。
- **rename/move**: `history.renameOccurred(from:to:)` で履歴内 URL を更新し、
  スタックを陳腐化させない（`SessionStore.noteRenamed` と同じ思想）。
- **重複防止**: 現在エントリと同一スナップショット（同じ dir+file）の push はスキップ。
  同じファイルの再選択で履歴が膨らまない。
- **進む履歴の破棄**: 戻った後に新しいナビゲーションを行うと、それ以降の「進む」履歴を
  破棄（ブラウザ標準）。

## テスト

- **`NavigationHistory` 単体テスト（Swift Testing, `befoldTests/`）**:
  push / goBack / goForward、進む履歴の破棄、重複スキップ、
  `canGoBack`/`canGoForward`、`backEntries`/`forwardEntries` の順序、`jump`、
  `renameOccurred`。純ロジックなので網羅的に。
- **`ViewerWindowController`（`@MainActor`）**: ユーザー操作で履歴が積まれること、
  戻る/進むで `fileListModel` の状態が更新されること、`isNavigatingHistory` 中に
  push されないこと。AAA、実ファイルは一時ディレクトリ。
- **サイドバーのボタン/長押しメニューの見た目・操作**: WKWebView 層同様、自動テスト
  対象外。リリース前手動チェック。

## 実装順序（TDD）

1. `NavigationHistory` + `HistoryEntry` を単体テスト先行で実装。
2. `ViewerWindowController` に history 保持・push・applyEntry・ガード・
   `refreshHistoryState`・rename 連携を追加（`@MainActor` テスト）。
3. `FileListModel` に履歴プロパティ追加。
4. `FileListView.header` にボタン + 履歴メニュー + コールバックを追加し配線。
5. ローカライズキー（ツールチップ）追加。
6. 手動スモークチェック。
