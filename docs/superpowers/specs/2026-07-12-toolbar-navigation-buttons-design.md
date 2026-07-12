# 戻る・進むボタンのツールバー移設と行番号トグルの統合 設計

<!-- derived-from ./2026-07-07-sidebar-navigation-history-design.md -->
<!-- derived-from ./2026-07-07-line-numbers-design.md -->

## 背景と目的

戻る・進むボタンは現在サイドバー(`FileListView`)のヘッダーにあるが、
Markdown のリンク移動が増えたことで「サイドバーを開かずにページ(ファイル)を
移動する」ユースケースが主流になった。サイドバーを畳むと視認可能な操作手段が
スワイプしかなくなるため、ナビゲーション操作をウィンドウ上部のツールバーへ移す。

あわせて、ソースコードビュー専用バー `ViewerTopBar` に単独で置かれている
行番号トグルもツールバーへ統合し、`ViewerTopBar` を廃止する。

## 変更後のツールバー構成

`NSToolbar`(unified スタイル)のアイテム並びを次のとおりにする。

```
[サイドバー開閉] ┃ [戻る][進む]  …flexibleSpace…  [行番号] [プレビュー⇄ソース]
  サイドバー側    ↑NSTrackingSeparatorToolbarItem   プレビュー側
```

- `.toggleSidebar`(既存・変更なし)
- **tracking separator**: `NSTrackingSeparatorToolbarItem(identifier:splitView:dividerIndex:)`
  を `ViewerSplitViewController` の `splitView`・divider 0 に連動させる。
  戻る・進むが常にプレビュー領域の左端に位置し、サイドバーを畳むと仕切りは
  自動的に消えて開閉ボタンの隣に並ぶ(Finder / Xcode と同じ挙動)
- **戻る・進む**: 既存の `HistoryButtonView`(NSButton サブクラス。クリックで移動、
  長押し/右クリック/Cmd+クリックで履歴メニュー)を `NSToolbarItem.view` として再利用する。
  SwiftUI ラッパー `HistoryNavigationButton`(NSViewRepresentable)は不要になるため削除
- `.flexibleSpace`(既存)
- **行番号トグル**: `list.number` アイコンのトグルボタン。**常時表示**し、
  コード系コンテンツ表示時(`ViewerStore.showsCodeContent`)以外は **disable** にする。
  on/off 状態は `ViewerStore.showLineNumbers` を反映(永続化キー `ShowLineNumbers` は既存のまま)
- **プレビュー⇄ソース切替セグメント**(既存・変更なし)

## 状態の伝搬

ツールバーは AppKit(`ViewerWindowController` が `NSToolbarDelegate`)なので、
SwiftUI の自動追従は使えない。以下の既存経路に合わせる。

- 戻る・進むの enable/disable と履歴メニュー内容:
  `FileListModel.canGoBack / canGoForward / backHistory / forwardHistory` を参照する。
  現在 `FileListView` が SwiftUI で監視している状態を、`ViewerWindowController` が
  履歴更新時(`SidebarNavigator` 経由の遷移完了時)にツールバーアイテムへ反映する
- action 経路は既存のまま: ボタン → `ViewerWindowController.navigateHistory(by:)`
  → `SidebarNavigator.navigateHistory(by:)`
- 行番号トグル: action は `ViewerWindowController.toggleLineNumbers(_:)`(既存メニューと共通)。
  enable 状態と on/off 表示は `ViewerStore` の変化に合わせて更新する
  (モード切替・ファイル切替時に `updateModeToggleAppearance` と同様の更新点で反映)

## サイドバーとプレビュー領域の変更

- `FileListView` ヘッダーから戻る・進むボタンを削除する。ヘッダーにはディレクトリ名
  (と既存の表示要素)のみ残す
- `ViewerTopBar` を削除し、`ViewerContentView` の条件分岐
  (`showsCodeContent` による VStack 先頭への挿入)を除去する。
  これによりモード切替時に 22pt のバーが出没してコンテンツがずれる挙動が解消される

## メニューとキーボードショートカット

現状、戻る・進むだけメニュー・ショートカット未対応(行番号 Cmd+L、
サイドバー Cmd+S、ソース切替 Cmd+U は対応済み)なので、あわせて追加する。

- View メニューに「戻る」(Cmd+[)・「進む」(Cmd+])を追加
  (`MainMenuBuilder`、ローカライズキー `menu.view.goBack` / `menu.view.goForward`)
- ターゲットは `ViewerWindowController` のハンドラ(内部で `navigateHistory(by:)` を呼ぶ)
- `validateMenuItem` 相当の既存パターンに従い、履歴がないときは disable
- トラックパッド水平スワイプ(`SwipeHistoryNavigation`)は変更なし

## アクセシビリティ

- 各ツールバーアイテムに `label` / accessibility label を設定する:
  戻る・進む・行番号(既存のローカライズ体系に合わせる)
- 戻る・進むはキーボードショートカット追加により VoiceOver 利用時の操作手段も改善される

## テスト

- `NavigationHistory` / `FileListModel` の既存ユニットテストは変更なし(ロジック非変更)
- `MainMenuBuilder` にテストがあれば、戻る・進むメニュー項目(キー・action)の検証を追加
- ツールバー・ボタン外観は GUI 層のためリリース前手動チェック
  (サイドバー開閉時の仕切り追従、モード切替時の行番号 disable、長押し履歴メニュー)

## 検討した代替案

- **プレビュー領域内のバー/オーバーレイに配置**: 操作列が 2 段になり macOS の慣習から
  外れるため不採用
- **サイドバーに残してショートカットのみ追加**: サイドバーを閉じた状態での視認可能な
  操作手段がなく、目的を満たさないため不採用
- **行番号ボタンをソースモード時のみ表示**: アイテムの動的挿入・削除でツールバーが
  ちらつくため、常時表示・プレビュー時 disable を採用(ユーザー確認済み)
