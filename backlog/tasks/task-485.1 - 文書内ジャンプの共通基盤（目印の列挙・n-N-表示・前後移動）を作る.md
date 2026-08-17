---
id: TASK-485.1
title: 文書内ジャンプの共通基盤（目印の列挙・n/N 表示・前後移動）を作る
status: To Do
assignee: []
created_date: '2026-08-14 13:17'
updated_date: '2026-08-17 08:38'
labels: []
milestone: m-6
dependencies:
  - TASK-510
parent_task_id: TASK-485
priority: medium
type: task
ordinal: 712000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`viewer-src/find.js` は「マッチ列 + 現在位置 + n/N 表示 + 前後移動 + 現在位置ハイライト
+ scrollIntoView」を 1 つのクロージャに閉じ込めている（`_createFindController()` :39）。
見出し・差分・関数定義のジャンプは、**列挙の仕方だけが違って残りは同じ**。

そこで、目印（target）の列を返すプロバイダを受け取り、位置管理と UI を担う
共通コントローラを切り出す。find.js 自体をこの基盤へ載せ替えるかは設計判断
（載せ替えるなら既存の検索の挙動を変えないことを担保するテストが要る）。

## 設計上の論点（`/review-design` で扱うこと）

- 検索バーと**同じバーを使い回す**のか、別バーを出すのか。同時に開ける必要はあるか
- 目印の粒度が「要素」か「行（tr）」かで、ハイライトの当て方が変わる。`mark.mmd-find-match-current`
  は inline 要素前提で、行ハイライト用の CSS は現状無い（`style.css:627/632`）
- 再描画・チャンク追記への追従。`render.js:74 _mmdFindRefreshAfterRender()` と
  `find.js:349 setTruncated` が既にある。ここへ相乗りするか、同型の口を増やすか
- Swift 側のコマンドの持ち方。`ViewerBridge.PlainFunction`（:25-48）へ足す関数の数を
  対象ごとに 3 本ずつ増やすのか、対象を引数に取る 1 組にするのか
- キーバインドの割り当て（⌘F / ⌘G / ⇧⌘G は検索が使用済み。`MainMenuBuilder.swift:136-148`）
- 表示モードごとの可否判定は `ViewerCapabilities`（`befold/Viewer/ViewerCapabilities.swift:16,59`）
  に `canFind` の前例がある。同じ形で導出する

## 注意

`viewer-src/main.js` へ export すれば `expose.ts:21 exposeGlobals()` が自動で
window に載せる。Swift 側は `ViewerBridge` のテストが `function _mmdX()` の
定義トークン存在を検証している（:45）ので、追加関数も同じ規約に従うこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 目印の列挙を差し替えるだけで別種のジャンプが作れる形になっている
- [ ] #2 現在位置と総数の表示、前後移動、現在位置のハイライトとスクロールが共通化されている
- [ ] #3 再描画とチャンク追記のあとで目印の列が再構築される
- [ ] #4 既存の検索窓の挙動（マッチ数・移動・ハイライト・truncated 表示）が変わっていないことをテストで担保している
- [ ] #5 この基盤の上で少なくとも 1 種類の目印が動くところまで確認できている
<!-- AC:END -->
