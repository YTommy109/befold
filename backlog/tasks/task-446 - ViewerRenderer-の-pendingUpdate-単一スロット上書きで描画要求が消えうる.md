---
id: TASK-446
title: ViewerRenderer の pendingUpdate 単一スロット上書きで描画要求が消えうる
status: To Do
assignee: []
created_date: '2026-08-11 11:01'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 674000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerRenderer.handleNavigationFailure`(BefoldApp/BefoldRenderKit/ViewerRenderer.swift:358-368) が `exitDirectHTMLMode` → `reloadViewerHTML`(ViewerRenderer+RenderHelpers.swift:214-228) を呼び、`pendingUpdate` を**無条件に上書き**する。`pendingUpdate` はスロットが 1 つしかない（ViewerRenderer.swift:130、消費は :299-300）。

再現順序:

1. `.html` ファイルで直接 HTML モードへ入る（ViewerRenderer+ContentUpdate.swift:134 で `isReady = false`、`loadFileURL` 開始）
2. その間に別ファイルへ切り替わると、更新は `pendingUpdate` に積まれるだけ（ContentUpdate.swift:235）
3. ここで 1 のナビゲーションが失敗すると（ファイル削除・読めない・policy cancel 由来の "Frame load interrupted" 等）`handleNavigationFailure` が走り、**積まれていた描画要求が空 completion に置き換わって消滅**する。同時に `rendered.reset()`（:351）
4. 以後 SwiftUI 側の値は変わらないため updateContent を呼び直す契機が無く、空の viewer.html のまま残る

`.cancel` を返すローカルファイルリンクのクリック（ViewerRenderer+DirectHTMLLinkPolicy.swift:40-47）は 2→3 の順序を作りやすい経路。

TASK-445 の調査中に発見した。TASK-445 の報告事象（切替元が .swift / .sh）とは前提が異なるため別タスクとする。世代番号でもミラー比較でもなく単一スロットの上書きが原因なので、既存のガードのどれにも掛からない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 pendingUpdate に積まれた描画要求が、ナビゲーション失敗による viewer.html 再ロードで失われない
- [ ] #2 .html を直接 HTML モードで読み込み中に別ファイルへ切り替え、元のナビゲーションが失敗しても、切替先の内容が表示される
- [ ] #3 上記を破ると落ちるユニットテストがある
<!-- AC:END -->
