---
id: TASK-485.34
title: ジャンプバーを開いている間も cmd+G / cmd+shift+G で次・前の目印へ移動できるようにする
status: To Do
assignee: []
created_date: '2026-09-25 13:47'
labels:
  - jump
dependencies: []
parent_task_id: TASK-485
ordinal: 835000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

検索では cmd+G / cmd+shift+G（Edit > 次を検索 / 前を検索）で前後のマッチへ移れるが、統合バーがジャンプのモードのときは何も起きない。ジャンプの前後移動は Enter / shift+Enter だけ（viewer-src/keyboard.ts の resolveJumpNavigationKey）。

## 現状（実測 / 2026-09-25 時点）

- Edit メニューの findNext / findPrevious は WebViewDocumentRenderer.findNext → ViewerFindBridge.findNextScript → _mmdFindNextIfOpen（viewer-src/find.ts）と伝わる
- _mmdFindNextIfOpen は _mmdFind.isOpen() = isBarOpen('find') を見るので、ジャンプのモードでは無視される
- ジャンプ側には _mmdJumpNextIfOpen / _mmdJumpPrevIfOpen（viewer-src/jump.ts）が既にある

## 検討の経緯

ジャンプを開くキーとして cmd+G・cmd+J も比べたうえで、開くキーは cmd+shift+F のまま（TASK-485.28）とした。cmd+G は macOS の慣習で「次の結果へ進む」操作であり、開く操作には合わない。cmd+J は macOS 標準の「選択部分へジャンプ」と意味がぶつかり、cmd+F / cmd+shift+F が同じキーでトグルする組み合わせも崩れる。一方、ジャンプバーはバーのモード違いなので、検索と同じ cmd+G / cmd+shift+G で前後に移れるほうが一貫する。

## 注意

- 開いているのが検索かジャンプかで振り分ける先を 1 箇所に置く（JS の現在のバーのモードが唯一の持ち主。Swift 側に開閉状態の写しを作らない）
- PDF 面はジャンプを持たないので、検索の挙動を変えない
- メニュー項目の表示名（次を検索 / 前を検索）をジャンプ中にどう見せるかも決める
- 紹介サイトのショートカット表（TASK-485.25）に載る前、ゲート撤去（TASK-485.16）より前に決めて入れる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ジャンプバーを開いている間、cmd+G で次の目印、cmd+shift+G で前の目印へ移動し、末尾・先頭で巡回する（Enter / shift+Enter と同じ振る舞い）
- [ ] #2 検索バーを開いている間の cmd+G / cmd+shift+G の振る舞いは変わらない（Web 面・PDF 面とも）
- [ ] #3 バーが閉じている間は cmd+G / cmd+shift+G が何もしない（従来どおり）
- [ ] #4 検索とジャンプのどちらへ振り分けるかを決める判定が 1 箇所にあり、それを破ると落ちるテストがある
- [ ] #5 Edit メニューの項目の有効・無効と表示名が、ジャンプ中の挙動と食い違わない
<!-- AC:END -->
