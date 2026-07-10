# サイドバートグルのツールバーボタン化

<!-- supersedes ./2026-07-09-collapsed-sidebar-handle-design.md -->

## 概要

サイドバー（ファイル一覧）が閉じている間の再表示手段を、左端の常時表示ハンドル（PR #155）から、ツールバーのシステム標準サイドバーボタンに置き換える。見た目・挙動を macOS 標準（Finder / Mail / Notes 相当）に揃える。

## 背景

- PR #155 で左端ハンドル（`CollapsedSidebarHandleView`）を実装したが、見た目が macOS らしくなく気に入らなかった
- AppKit には `NSToolbarItem.Identifier.toggleSidebar` というシステム標準の識別子があり、これをツールバーに含めるだけで、アイコン・開閉状態・アクション配線を OS 側が自動処理する
- サイドバーの開閉状態そのものは既に `ViewerSplitViewController`（`NSSplitViewController` サブクラス）の `sidebarItem.isCollapsed` で一元管理されており、変更不要

## 設計

### ツールバーへのシステム標準ボタン追加

`ViewerWindowController.swift` の `NSToolbarDelegate` 実装を変更する。

- `toolbarDefaultItemIdentifiers` の先頭に `.toggleSidebar` を追加: `[.toggleSidebar, .flexibleSpace, Self.sourceToggleItemIdentifier]`
- `toolbarAllowedItemIdentifiers` にも `.toggleSidebar` を追加
- アイコン画像・有効/無効・クリック時のアクション（`toggleSidebar(_:)` 呼び出し）は AppKit が自動的に行うため、`toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` や `validateToolbarItem` に独自の分岐を追加する必要はない

### 左端ハンドルの削除

- `CollapsedSidebarHandleView.swift` をファイルごと削除
- `ViewerSplitViewController.swift` から以下を削除:
  - `collapsedHandleView` プロパティとその生成・レイアウト制約
  - `syncCollapsedHandleVisibility()`
  - `viewWillAppear()` / オーバーライド済み `toggleSidebar(_:)` / `splitViewDidResizeSubviews` 内にある、上記メソッドへの呼び出し
- 一方で維持するもの（ハンドルとは無関係な既存ロジック）:
  - `viewWillAppear()` の `forceSidebarVisible` による初回 collapse 制御
  - `toggleSidebar(_:)` オーバーライド内の、展開後にサイドバーへフォーカスを移す `makeFirstResponder` 処理

### メニュー・ショートカットとの関係

`MainMenuBuilder.swift` の「サイドバーを表示/非表示」メニュー項目（⌘S、`#selector(NSSplitViewController.toggleSidebar(_:))`）は変更しない。ツールバーボタン・メニュー・⌘S はすべて同じ `toggleSidebar(_:)` に到達するため、三者は自然に同期する。

## 期待される挙動

- ツールバー左端（タイトルの左）にシステム標準の「サイドバー」アイコンボタンが表示される
- クリックで開閉、アイコンの見た目切り替えは OS が自動処理
- サイドバーが閉じていても、ツールバーボタン・View メニュー・⌘S のいずれからでも再展開できる
- ウィンドウ／タブの初期表示時の collapse 判定（`forceSidebarVisible`）は従来通り

## テスト方針

- `CollapsedSidebarHandleView` に対する既存テスト（あれば）を削除
- `ViewerSplitViewController` のテストのうち、ハンドル可視性同期を検証していたものを削除。`toggleSidebar(_:)` のフォーカス移動テストは維持
- ツールバー・ウィンドウ層は CLAUDE.md の規約通り自動テスト対象外のため、以下を手動チェックする:
  1. ツールバーのサイドバーボタンでサイドバーが開閉する
  2. ⌘S・View メニューからも開閉できる
  3. サイドバーを閉じた状態で新規ウィンドウ／タブを開いても、ツールバーボタンから再表示できる
  4. 左端ハンドルの表示が完全になくなっている
