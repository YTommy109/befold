# ブックマーク機能

## 背景

現状、頻繁に参照するファイルへ素早くアクセスする手段がない。ファイル単位でオン/オフできる「ブックマーク」を追加し、目印として使えるようにする。加えて、ブックマークしたファイルをメニューから一覧・オープンできるようにする（Open Recent と同様のアクセス手段）。

## 設計

### ストレージ: `BookmarkStore`

`App/RecentDocumentsStore.swift` と同型のクラスを新設する（`PathKeyedDictionary` は列挙 API を持たないため、一覧表示が必要な本機能には不向き）。

```swift
@MainActor
final class BookmarkStore {
    // UserDefaults key: "BookmarkedPaths"
    // 保存フォーマット: [String]（normalizedPathKey の配列）
    func isBookmarked(_ url: URL) -> Bool
    func toggle(_ url: URL)
    func bookmarkedURLs() -> [URL]
    func noteRenamed(from: URL, to: URL)
}
```

- 上限件数なし（Recent と異なりユーザーの明示操作でのみ増減するため、自動プルーニングは不要）
- 順序は保存時のまま管理しない。表示時（メニュー構築時）に `lastPathComponent` でアルファベット順ソートする
- rename 時は `ViewerWindowManager` の既存 rename フック（`RecentDocumentsStore.noteRenamed` を呼んでいる箇所）に併せて `bookmarkStore.noteRenamed(from:to:)` を呼ぶ
- ファイル削除・移動で消えたエントリの自動削除はしない（Recent と同じ挙動）。一覧に表示され続けるが、選択時のファイル不存在チェック・アラートは `AppDelegate.openViewer(for:)` の既存経路（`FileNotFoundUI`）にそのまま乗る

### 注入経路

`ZoomStore` と同じ配線パターン:

`AppDelegate.init` で生成 → `ViewerWindowManager.init` に渡す → `ViewerWindowController.init` に渡す

### ツールバーボタン

`ViewerWindowController` の `NSToolbar` に `bookmarkItemIdentifier` を追加する。行番号トグルボタン（`makeLineNumbersToolbarItem()`）と同じ実装パターン:

- `NSButton`（`bezelStyle = .texturedRounded`）
- SF Symbol: オフ = `bookmark`、オン = `bookmark.fill`
- オン時は `contentTintColor` をアクセントカラーに設定
- `menuFormRepresentation` を設定し、ツールバーオーバーフロー時もメニューから操作可能にする
- ツールチップ: 「ブックマークする」/「ブックマーク解除」
- ファイル切り替え時（`ViewerStore.openFile` 連動）に `updateBookmarkToolbarItem()` を呼び、新しいファイルの状態で見た目を再評価する

複数ウィンドウ/タブで同一ファイルを開いている場合、片方でのトグルは他方のツールバー表示に即時連動しない（次にそのウィンドウがアクティブになった時に再評価される）。不可視ファイルトグルのような全ウィンドウ連動は本機能では行わない。

### View メニュー項目

`MainMenuBuilder.swift` の View メニューに「ブックマークする」/「ブックマーク解除」を追加する。不可視ファイルトグルと同じパターン:

- `AppDelegate.toggleBookmark(_:)` → キーウィンドウの `ViewerWindowController` に処理委譲
- `validateMenuItem` で現在のファイルのブックマーク状態に応じてタイトルを動的切替
- キーボードショートカット: `⌘D`（実装時に既存ショートカットと衝突しないか `MainMenuBuilder.swift` を確認して確定する）

### Bookmarks サブメニュー

File メニュー内、Open Recent と並列に「Bookmarks」サブメニューを新設する。`RecentDocumentsMenuController` と同じ `NSMenuDelegate` パターンで `BookmarksMenuController` を実装する:

- `menuNeedsUpdate(_:)` で毎回 `menu.removeAllItems()` してから再構築
- `bookmarkStore.bookmarkedURLs()` を `lastPathComponent` でアルファベット順ソートして列挙
- 各 `NSMenuItem` の `representedObject` に URL、アイコンは `NSWorkspace.shared.icon(forFile:)`
- 選択時のアクションは Open Recent と同じ `openHandler`（`AppDelegate.openViewer(for:)`）を再利用
- 一覧からの個別解除・一括クリアは設けない（該当ファイルを開いてツールバー/View メニューでトグルオフする運用とする）

## 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `App/BookmarkStore.swift`（新規） | ブックマーク永続化・toggle・列挙・rename追従 |
| `App/BookmarksMenuController.swift`（新規） | Bookmarks サブメニューの動的構築（`RecentDocumentsMenuController` を参考に実装） |
| `App/AppDelegate.swift` | `BookmarkStore` 生成・注入、`toggleBookmark(_:)`、`validateMenuItem` 拡張、`BookmarksMenuController` の保持・配線 |
| `App/ViewerWindowManager.swift` | `BookmarkStore` を `ViewerWindowController` へ注入、rename フックで `noteRenamed` 呼び出し |
| `App/ViewerWindowController.swift` | ツールバーに `bookmarkItemIdentifier` 追加、`makeBookmarkToolbarItem()`／`updateBookmarkToolbarItem()`、ファイル切り替え時の再評価 |
| `App/MainMenuBuilder.swift` | View メニューにブックマーク項目、File メニューに Bookmarks サブメニュー追加 |

## テスト

- `BookmarkStoreTests`（`RecentDocumentsStoreTests` があれば同形式で追加）: toggle の追加/削除、`isBookmarked` の判定、永続化（インスタンス跨ぎ）、`noteRenamed` でのキー引き継ぎ
- `BookmarksMenuController` はロジックが薄ければユニットテスト対象外（`RecentDocumentsMenuController` の扱いに合わせる）

## スコープ外

- ブックマークの色分け・タグ付け等の拡張属性（単純な on/off のみ）
- サイドバーのファイル一覧へのブックマークアイコン表示（ツールバーボタンの状態のみで十分という合意のため）
- 複数ウィンドウ/タブ間でのブックマーク状態の即時連動
- Bookmarks サブメニューからの個別削除・一括クリア機能
- 存在しなくなったファイルの自動的なブックマーク解除
