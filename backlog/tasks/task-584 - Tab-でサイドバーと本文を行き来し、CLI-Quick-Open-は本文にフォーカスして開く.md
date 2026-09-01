---
id: TASK-584
title: Cmd+← / Cmd+→ でサイドバーと本文を行き来し、CLI / Quick Open は本文にフォーカスして開く
status: Done
assignee: []
created_date: '2026-09-01 05:10'
updated_date: '2026-09-01 05:51'
labels:
  - ui
dependencies:
  - TASK-579
priority: high
type: feature
ordinal: 848000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-579 の残る論点に対するユーザーの判断（2026-09-01）。

## 背景

TASK-581 で「PDF を開いてもフォーカスはサイドバーに残す」と決めた（サイドバーを矢印で流し読みし続けられるようにするため）。その結果、**PDF を開いた直後にスペースを押しても何も起きない**——フォーカスはサイドバーにあり、サイドバーはスペースに割り当てを持たないため。面へ渡すには面を 1 回クリックするしかない。

## 決めたこと（ユーザー / 2026-09-01）

1. **Tab でサイドバーと本文を行き来する。** 双方向。
2. **CLI / Quick Open で開いたときは本文側にフォーカスを置く。** これらはサイドバーを操作して開いたわけではないので、本文に居るのが妥当。サイドバーの矢印操作・クリック由来のオープンは従来どおりサイドバーに残す（TASK-581 の決定を保つ）。

## 前提（着手前に確かめること）

- `makeFirstResponder` を呼ぶ箇所はプロダクトコードに 3 箇所しかなく、面を first responder にするコードは `PDFViewProxy.focusSurface()`（TASK-579 で集約）だけ。web 面（WKWebView）を first responder にするコードは存在しない。
- 面と web 面で「フォーカスを得る仕組み」に実装差は無く、どちらも AppKit 既定のクリック昇格に頼っている（TASK-579 の調査）。したがって Tab の受け口も両面で要る。
- Tab は web 面では DOM のフォーカス移動に使われる可能性がある。web 面での扱いは設計レビューで決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーにフォーカスがあるとき ⌘→ で本文へ移る
- [x] #2 本文にフォーカスがあるとき ⌘← でサイドバーへ移る
- [x] #3 サイドバーが畳まれているとき ⌘← のメニュー項目が無効になる（押しても壊れない）
- [x] #4 CLI で開いたウィンドウは本文にフォーカスがある
- [x] #5 Quick Open で開いた（切り替えた）ウィンドウは本文にフォーカスがある
- [x] #6 サイドバーの矢印操作・クリックで開いた場合はサイドバーにフォーカスが残る（TASK-581 の回帰テストが通る）
- [x] #7 web 面と PDF 面の両方で ⌘← / ⌘→ が働く
- [x] #8 2 つの操作が表示メニューに出ており、Help のショートカット一覧にも載る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計（ユーザーの判断 / 2026-09-01）

Tab は使わない。**web 面では Tab / Shift+Tab がブラウザ既定の文書内リンク送りに使われて
いる**ため（`viewer-src/keyboard.ts` はどちらも見ておらず既定処理に委ねている）、奪うと
Markdown 文書のリンクをキーボードで辿れなくなる。

代わりに **⌘→ = 本文へ / ⌘← = サイドバーへ** を表示メニューの項目として足す。

### なぜメニュー項目にするか

- AppKit がキーエクイバレントをレスポンダに関係なく拾うので、**面ごとにキーを受ける
  仕組みを作らなくてよい**（web 面に横取りの口を新設せずに済む）
- Help のショートカット一覧は `MenuShortcutCatalog` がメニューから収集するので、
  一覧への掲載が自動で付いてくる（AC #8）
- 空いていることを実測済み: 履歴の戻る/進むは `⌘[` / `⌘]`、メニューに矢印の割り当ては
  1 件も無い。PDF 面は Cmd 付きを `super` へ流す約束、web 面は `metaKey` で早期 return

### 衝突の手当て

`SidebarKeyAction.action` の `case .return, .rightArrow, "l"` には修飾キーの条件が無く、
現状 ⌘→ がサイドバーの「開く / 降りる」に一致する。メニューが先に拾う見込みだが、
**純粋関数側にも明示の分岐を入れて意図を固定する**（Cmd 付きの左右は `.ignored`）。

### 契機の伝え方: ワイヤ表現に触らない

「CLI / Quick Open で開いたら本文へ」は `CLIOpenOptions` にフラグを足さない。あれは
CLI とアプリ間の Codable なワイヤ表現で、セッション復元も流用しているため波及が大きい。
**契機を知っているのは呼び出し元**なので、呼び出し元が開いた後に本文へフォーカスする。

- CLI: `DocumentOpener.openPaths(_:options:)`
- Quick Open: `QuickOpenCoordinator.open(_:)`（アクティブなビューアがあれば `switchFile`、
  無ければ `openInNewWindow`。**どちらの経路にも要る**）

サイドバー由来（`fileListDidSelectFile` → `switchFile`）は何もしないので、TASK-581 の
決定はそのまま保たれる。

### 面へフォーカスする口

- PDF: `PDFViewProxy.focusSurface()`（TASK-579 で作成済み）
- web: `WebViewProxy` に同等の口を新設する（`webView` は public なので到達可能）
- どちらを使うかは窓が知っている（`DocumentSurfaces`）。`ViewerWindowController` に
  `focusContentSurface()` を置き、面の選択をそこに閉じる

### 手順

1. `WebViewProxy.focusSurface()` を足す
2. `ViewerWindowController` に `focusContentSurface()` / `focusSidebar()` を足す
3. メニュー項目 2 つと `validateMenuItem`（畳んでいるとき ⌘← を無効化）
4. `SidebarKeyAction` に Cmd 付き左右の明示分岐
5. CLI / Quick Open の呼び出し元から `focusContentSurface()`
6. Localizable.xcstrings に 2 キー
7. テスト（純粋関数の割り当て / メニューの有効・無効 / 契機ごとのフォーカス先）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 途中で 2 回、割り当てを変えた（実測で前提が崩れたため）

1. **Tab → ⌘← / ⌘→**: web 面では Tab / Shift+Tab がブラウザ既定の文書内リンク送りに
   使われている（`viewer-src/keyboard.ts` はどちらも見ておらず既定処理に委ねている）。
   奪うと Markdown 文書のリンクをキーボードで辿れなくなるため、矢印へ移した。
2. **⌘← は「空いている」という私の報告が誤りだった。** メニューと履歴（⌘[ / ⌘]）だけを
   見て「空き」と判断したが、サイドバーには `FileListViewNavigationKeyTests` の
   「Cmd+← は従来どおり上位フォルダーへ移動する」という既存の割り当てとテストがあり、
   実装したところこれが落ちた。

## 同じキーを文脈で分ける（ユーザーの指摘）

「⌘← で上位フォルダーへ移動するのはフォーカスがサイドバーにある時だけでは」という指摘を
受けて、その形にした。**無効なメニュー項目はキーエクイバレントを消費しない**ので、
サイドバーにフォーカスがあるときに ⌘← の項目を無効にすると、キーはそのままサイドバーの
キー処理へ落ちて従来どおり動く。判定は `ViewerMenuValidator.validateFocusTraversalItem`
の 1 箇所だけに置いた。

## 契機の伝え方

`CLIOpenOptions` にフラグを足さなかった。あれは CLI とアプリ間の Codable なワイヤ表現で、
セッション復元も流用しているため波及が大きい。**契機を知っているのは呼び出し元**なので、
`DocumentOpener.openViewer(for:focusesContent:)` を受け口にして、CLI（`openPaths`）と
Quick Open（`QuickOpenCoordinator.open` / `openInNewWindow`）だけが true を渡す。
サイドバー由来（`fileListDidSelectFile` → `switchFile`）は何もしないので TASK-581 の決定は保たれる。

## 実機での実測（2026-09-01）

| 操作 | 測定結果（AXFocusedUIElement） |
| --- | --- |
| PDF を開いた直後 | `AXOutline`（サイドバー） |
| ⌘→ | `AXGroup`（説明「書類」＝ PDF 面） |
| 本文で ⌘← | `AXOutline` へ戻る |
| サイドバーで ⌘← | フォーカスは `AXOutline` のまま、**ウィンドウ名が many.pdf → pdf** ＝上位フォルダーへ移動 |
| `befold-cli sample/class.mmd` | `AXWebArea`（web 面）。**web 面でも focusSurface が効く**ことを同時に確認 |

Quick Open だけは合成キー入力がパネルの入力欄へ届かず実機で測れなかったため、
宛先の振り分け（`DocumentSurfaceDispatchTests`）で押さえた。

## テストが空振りしないことを 2 通りの破壊で確認

- サイドバーが ⌘→ を譲らない → `FocusTraversalTests` が落ちる
- 畳んでいても ⌘← を有効にする → 同上

## 検証

- `swift test`: 1860 tests / 303 suites 通過
- swiftlint: `origin/main` との差分ゼロ。**初回は 2 件の新規違反が出た**
  （`ViewerMenuValidator` の `cyclomatic_complexity` と `DocumentCommandControllerTests` の
  `file_length`）。閾値は緩めず、判定を `validateFocusTraversalItem` へ切り出し、
  テストは宛先の振り分けを見ている `DocumentSurfaceDispatchTests` へ移して解消した
- markdownlint / check-doc-symbols / check-doc-citations / 型グループ: 通過

## ⌘← の上位フォルダー移動を廃止した（ユーザーの判断 / 2026-09-01）

「上位フォルダへ上がる方法が多過ぎる。⌘↑ があるので ⌘← は廃止してよい。Finder も
⌘← は上位へ移動しない」という指摘を受けて、サイドバーの ⌘← を `.ignored` にした。

**これで文脈依存の判定が要らなくなった。** 直前に入れていた「サイドバーにフォーカスが
あるときだけ ⌘← の項目を無効にする」（`isSidebarFocused`）を撤去し、判定は
「畳んでいるときだけ無効」に戻した。単純化として素直で、`ViewerMenuValidationSource` の
要求も 1 つ減った。

上へ出る手段は ⌘↑ と delete に残っている（`FocusTraversalTests` の
「上位フォルダーへは ⌘↑ と delete で行ける」が、外した副作用でキーボードだけでは
上へ行けなくなっていないことを固定する）。

### 実機での再確認（2026-09-01）

| 操作 | 結果 |
| --- | --- |
| ⌘→ | `AXWebArea`（web 面）へ |
| ⌘← | `AXOutline`（サイドバー）へ戻る |
| サイドバーで ⌘← | 上位へ移動しない（ウィンドウ名 class.mmd のまま） |
| ⌘↑ | ウィンドウ名が class.mmd → sample ＝上位移動は残っている |

`FileListViewNavigationKeyTests` の「Cmd+← は従来どおり上位フォルダーへ移動する」は
仕様変更に合わせて書き換えた（`.handled` → `.ignored`、移動先 nil）。

なお最初のコミット時に型グループの上限超過（`ViewerWindowController` 902 行 / 上限 900）が
出ていたので、窓側に置いた 2 つの `@objc` メソッドの doc を短くして解消した（理由は
メニュー構築側と判定側に既に書いてあり、二重に持つ必要が無い）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーと本文のあいだをキーボードで行き来できるようにした（⌘→ で本文へ、⌘← でサイドバーへ）。当初 Tab を検討したが、web 面では Tab / Shift+Tab がブラウザ既定の文書内リンク送りに使われているため矢印へ移した。⌘← はサイドバーの「上位フォルダーへ移動」と重なるので、メニュー項目の有効判定で文脈を分けた——無効なメニュー項目はキーエクイバレントを消費しないので、サイドバーに居るときはキーがそのまま落ちて従来どおり動く。あわせて CLI と Quick Open で開いた窓は本文にフォーカスを置くようにした（契機は呼び出し元が渡す。ワイヤ表現の CLIOpenOptions には足さない）。実機で ⌘→ / ⌘← の両方向、サイドバーでの ⌘← が上位フォルダー移動のままであること、CLI 起動時に web 面へフォーカスが載ることを AX で確認。swift test 1860 件通過、swiftlint 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
