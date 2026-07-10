# 検索結果の前後移動ショートカット（⌘G / ⌘Shift+G）設計

## 背景・目的

現在、検索結果の前後移動は検索フィールドにフォーカスがある状態での
`Enter` / `Shift+Enter` でのみ可能。macOS ネイティブアプリの慣習に合わせ、
`⌘G`（次を検索）/ `⌘Shift+G`（前を検索）をメニュー項目・グローバルショートカットとして追加する。

## 挙動

- 検索バーが開いている間のみ有効。閉じている間は `⌘G` / `⌘Shift+G` を押しても
  何も起きない（Safari のように「閉じた状態から開いて検索」はしない）。
- メニュー項目自体は HTML 直接表示モード（`isDirectHTMLMode`）以外では常に有効
  （グレーアウトしない）。開閉判定は JS 側の `_mmdFindIsOpenFlag` のみが持つ
  単一ソースであり、`NSMenuItem` の `validateMenuItem(_:)` は同期呼び出しのため
  WKWebView 側の状態を都度問い合わせられない。Swift 側に開閉状態を複製すると
  二重管理になるため、あえてメニュー項目の見た目では表現せず、実行時に JS 側で
  no-op にする方式を採る（「Swift 側に新しい状態を追加しない」という設計方針を優先）。
- 開いている間は、フォーカス位置に関わらずウィンドウ全体で動作する
  （メニュー項目の `keyEquivalent` によるグローバルショートカットのため）。

## 変更箇所

<!-- derived-from #背景目的 -->

1. **`viewer.html`**: `_mmdFindIsOpen()` が `false` の場合は何もしない薄いラッパー
   `_mmdFindNextIfOpen()` / `_mmdFindPrevIfOpen()` を追加し、内部で既存の
   `_mmdFindNext()` / `_mmdFindPrev()` を呼び出す。開閉状態の判定は既存の
   `_mmdFindIsOpenFlag` を単一ソースとして使い、新しい状態は増やさない。
2. **`ViewerBridge.swift`**: `openFindScript` と同じパターンで
   `findNextScript = "_mmdFindNextIfOpen()"` / `findPrevScript = "_mmdFindPrevIfOpen()"`
   を追加。
3. **`ViewerWindowController.swift`**: `find(_:)` と同じ形で
   `@objc func findNext(_ sender: Any?)` / `@objc func findPrevious(_ sender: Any?)` を追加。
   `webViewProxy.isDirectHTMLMode` のときは `find(_:)` 同様に無効化
   （`validateMenuItem(_:)` に判定を追加）。
4. **`MainMenuBuilder.swift`**: Edit メニューの「検索…」項目の下に2項目追加。
   - 次を検索: `keyEquivalent: "g"`, `keyEquivalentModifierMask: [.command]`
   - 前を検索: `keyEquivalent: "g"`, `keyEquivalentModifierMask: [.command, .shift]`
5. **`Localizable.xcstrings`**: `menu.edit.findNext`（`次を検索` / `Find Next`）、
   `menu.edit.findPrevious`（`前を検索` / `Find Previous`）を追加。

## テスト方針

WebView/GUI 層は自動テスト対象外（プロジェクト規約）のため、実機での手動確認とする。

- 検索バーを開いていない状態で `⌘G` / `⌘Shift+G` を押しても何も起きないこと
  （このとき Edit メニュー項目自体はグレーアウトしない。上記「挙動」参照）。
- 検索バーを開いた状態で `⌘G` を押すと次のマッチへ、`⌘Shift+G` で前のマッチへ移動すること。
- 検索フィールド外（プレビュー領域）にフォーカスがあっても動作すること。
- HTML 直接表示モード（`isDirectHTMLMode`）では両メニュー項目が無効化されること。
