---
id: TASK-469
title: フォルダー提示中もウィンドウタイトルが直前のファイル名のまま残る
status: Done
assignee: []
created_date: '2026-08-13 06:27'
updated_date: '2026-08-13 06:53'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 692000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 現象

サイドバーでフォルダーを選択してプレビューエリアにフォルダー一覧を表示しているとき、ウィンドウタイトルが直前に開いていたファイル名のままになる。プロキシアイコン（`representedURL`）も同様に古いファイルを指したまま。

## 調査結果（原因）

タイトル設定の実装は 1 箇所（`BefoldApp/befold/App/ViewerWindowChrome.swift:52-55` の `ViewerWindowChrome.applyURL(_:to:)`）で、呼び出し元 3 箇所はすべて「ファイル URL が変わったとき」に限られる。

- ウィンドウ生成 `BefoldApp/befold/App/ViewerWindowChrome.swift:42`
- ファイル切替 `BefoldApp/befold/App/ViewerWindowController+FileNavigation.swift:63`（`performFileSwitch` → `applyURLToWindow` `同:119-122`）
- リネーム追随 `BefoldApp/befold/App/ViewerWindowController+FileNavigation.swift:79`

フォルダー選択は `fileListModel.selection` を書くだけでファイル URL は動かない（`BefoldApp/befold/Viewer/FileListView.swift:157-175`、`BefoldApp/befold/App/SidebarNavigator+FolderNavigation.swift:15-33` はウィンドウに触れない）。提示対象変化の唯一の通知点 `FileListModel.notifyPresentationTargetChangeIfNeeded`（`BefoldApp/befold/Viewer/FileListModel.swift:147-152`）の結線先 `BefoldApp/befold/App/ViewerWindowAssembler.swift:200-204` は、ツールバー再同期とサイドバーへのフォーカスのみでタイトル更新を行っていない。

## 方針の候補

タイトルの真実の源を `fileURL` ではなく `fileListModel.previewTarget`（`.folder(url)` ならそのフォルダー名）に切り替え、`ViewerWindowAssembler.swift:200-204` の提示対象変化フックからも `ViewerWindowChrome.applyURL` 相当を呼ぶ。導出点を 1 つに保つ点で ADR 0002 の方針に沿う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダー提示中はウィンドウタイトルがそのフォルダー名になる
- [x] #2 フォルダー提示中は representedURL がそのフォルダーを指す
- [x] #3 ファイル提示へ戻るとタイトル・representedURL がそのファイルに戻る
- [x] #4 タイトル導出点が 1 箇所のままであること（ファイル用・フォルダー用に経路を二重化しない）
- [x] #5 上記を検証するユニットテストを追加し、修正を戻すと落ちることを確認済み
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 方針（review-design チェックリストを適用）

タイトルの真実の源を `fileURL` から `FileListModel.previewTarget` へ移す。導出は
`ViewerWindowChrome.applyURL(_:presenting:to:)` の 1 箇所だけに置き（AC #4）、
`previewTarget.folderURL ?? fileURL` で決める。

1. `ViewerWindowChrome.applyURL` に提示対象を **既定値の無い引数** で渡させる
   （渡し忘れがコンパイルエラーになる。既定値だと静かに文書名へ戻る経路ができる）。
2. `ViewerWindowController.applyURLToWindow` が `fileListModel.previewTarget` を渡す。
   ファイル切替中は ViewerStore の現在 URL が未更新のため、文書側は引数で受け続ける。
3. 契機を 1 つ足す: `ViewerWindowAssembler.wirePresentationTargetChange` から
   `applyURLToWindow(controller.fileURL)` を呼ぶ。フォルダー選択ではファイル URL が
   動かないため、既存の 3 契機（生成・切替・リネーム）では届かない。

## チェックリストの当たり
- 項目 1（判定の真実の源）: 提示対象という事実で判定する。データの有無では判定しない。
- 項目 3（消費経路の全列挙）: `ViewerWindowChrome.applyURL` の呼び出しは実測で
  生成・切替・リネームの 3 箇所のみ（`rg 'applyURLToWindow|ViewerWindowChrome.applyURL'`）。
  `representedURL` を読む本番コードは無い（テスト 1 件のみ）。
- 項目 5（順序）: 生成時は一覧未着で `.undetermined` -> 文書名。切替時に提示対象が
  遅れて変わる場合は提示対象変化フックが追随させる。
- 項目 6（高頻度経路）: `onPresentationTargetChange` は変化時のみ発火（既存の絞り込み）。
- 項目 9（担保）: 既定値なし引数 + ユニットテスト。
- 項目 10（行数）: ViewerWindowController グループは 803 行 / 例外上限 900、追加は数行。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- タイトル・representedURL の導出を `ViewerWindowChrome.applyURL(_:presenting:to:)` の 1 箇所へ集約し、`previewTarget.folderURL ?? fileURL` で決めるようにした（AC #4。ファイル用・フォルダー用の経路を二重化していない）。
- 提示対象は既定値の無い引数で受ける。渡し忘れがコンパイルエラーになる形にして、静かに文書名へ戻る経路を作らない。
- 契機を 1 つ追加: `ViewerWindowAssembler.wirePresentationTargetChange` から `applyURLToWindow` を呼ぶ。フォルダー選択ではファイル URL が動かず、既存の 3 契機（生成・切替・リネーム）では届かないため。

## 検証（実測）

- 新規 `ViewerWindowTitleTests` 3 件（フォルダー提示中のタイトル/representedURL、ファイル提示への復帰、Chrome の導出そのもの）。
- 修正を戻して落ちることを確認した（フック呼び出しの削除 + 導出を fileURL 固定に戻して実行）: 3 件すべてが "doc.mmd" のまま残って落ちる。
- 全テスト: `swift test --skip Integration --skip FileWatcherTests` -> 1367 tests / 209 suites すべて通過。
- swiftlint: 変更ファイルに警告 0 件。`scripts/check-type-group-size.sh` 通過（ViewerWindowController グループは例外上限 900 に対し 803 行）。

## 補足

同型の欠陥が履歴メニューのラベルにもあり（フォルダー提示のエントリでも直前のファイル名を出す）、TASK-468 の中で修正済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ウィンドウタイトルと representedURL の導出をファイル URL から提示対象（previewTarget）へ移し、ViewerWindowChrome.applyURL の 1 箇所に閉じた。提示対象変化フックから追随させることでフォルダー一覧表示中もタイトルが追随する。ViewerWindowTitleTests 3 件を追加し、修正を戻すと 3 件とも落ちることを実測。全 1367 テスト通過。
<!-- SECTION:FINAL_SUMMARY:END -->
