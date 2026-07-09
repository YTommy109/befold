# サイドバー折りたたみ中のハンドル表示

## 概要

サイドバー（ファイル一覧）を閉じている間、左端に常時表示される細いグレーの縦バーを追加する。バーはホバーで色が濃くなり、クリックでサイドバーを再表示する。ツールバーは変更せず、コンテンツ表示面積を最大限に保つ。

## 背景

- サイドバーの開閉は `NSSplitViewController`（`ViewerSplitViewController`）で管理しており、開閉トリガーはメニュー「表示 > サイドバーを表示/非表示」（⌘B、`MainMenuBuilder.swift`）のみ
- ツールバー（`ViewerWindowController`）にはサイドバー用のボタンが存在しない
- サイドバーを閉じると `NSSplitViewItem` の幅が 0 になり、視覚的な手がかりが一切残らないため、サイドバーが存在すること自体に気づけない
- ツールバーへのボタン追加も検討したが、コンテンツ（Markdown/コード）表示に使える面積を優先したいため見送り、常時薄く見える左端ハンドルで解決する

## 設計

### CollapsedSidebarHandleView（新規）

`BefoldApp/befold/App/CollapsedSidebarHandleView.swift` に追加する `NSView` サブクラス。描画とマウス操作のみを担当し、状態は持たない。

- 幅 4〜6pt、`ViewerSplitViewController` の view に leading/top/bottom を Auto Layout で固定
- 通常時: `NSSplitView` のデフォルトセパレーターと同等の控えめなグレーで描画
- ホバー時: `NSTrackingArea` で検知し、色を少し濃くする + `NSCursor.pointingHand` に変更
- ホバー時に `toolTip` で「サイドバーを表示 (⌘B)」を表示
- `mouseDown` で `NSSplitViewController.toggleSidebar(_:)` を呼び出す（メニュー⌘Bと同じアクション・アニメーションを再利用）

### 表示/非表示の同期

専用の状態フラグは持たず、毎回 `sidebarItem.isCollapsed` を見て `handleView.isHidden = !sidebarItem.isCollapsed` を設定するだけのシンプルな同期にする。同期を呼ぶタイミングは3箇所:

1. `viewWillAppear()` の初期表示処理（既存の `forceSidebarVisible` 判定の直後）
2. 既存でオーバーライド済みの `toggleSidebar(_:)`（メニュー⌘B経由）
3. `NSSplitViewDelegate.splitViewDidResizeSubviews(_:)`（ユーザーがディバイダーをドラッグして閉じた場合など、メニュー以外の経路もカバー）

### 配置

- 新規ファイル: `CollapsedSidebarHandleView.swift`
- `ViewerSplitViewController.swift` に数行追加（ハンドルビューの生成・配置・可視性同期の呼び出し）
- `ViewerWindowController.swift`（ツールバー）は変更しない

## テスト方針

CLAUDE.md の規約に従い、AppKit の描画・マウスインタラクション層は自動テスト対象外とし、リリース前の手動チェックで確認する。ロジック分岐を持たない純粋な描画・イベント処理のみのビューのため、ユニットテストで検証すべき対象がない。

手動チェック項目:

1. サイドバーを閉じた状態でハンドルが見える
2. ホバーで色とカーソルが変わる
3. ホバーでツールチップが出る
4. クリックでサイドバーが開く
5. ディバイダーをドラッグして閉じた場合もハンドルが表示される
