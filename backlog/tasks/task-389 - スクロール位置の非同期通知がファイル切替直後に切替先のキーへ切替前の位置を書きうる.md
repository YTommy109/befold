---
id: TASK-389
title: スクロール位置の非同期通知がファイル切替直後に切替先のキーへ切替前の位置を書きうる
status: To Do
assignee: []
created_date: '2026-08-09 11:10'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 645000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-388 の設計レビュー（項目 8「非同期で置き換わる表示状態の世代管理」）で見つけた、TASK-388 とは別系統の穴。

ViewerWindowController の renderer(_:didChangeScrollPosition:mode:)（BefoldApp/befold/App/ViewerWindowController.swift）は、保存先のキーを **呼び出し時点の fileURL** から都度求める。fileURL はファイル切替・リネームで書き換わるため、切替直後に JS から遅れて届いた「切替前ファイルのスクロール位置」の通知が、**切替先ファイルのキーへ** 保存されうる。

対になる saveCurrentScrollPosition(for:mode:) は呼び出し側がキーを明示指定する形（WebViewCommandController）になっており、そちらは同じ穴を持たない。通知側だけが現在値参照のまま残っている。

想定される症状: ファイルをすばやく切り替えると、切替先の文書が切替前の文書のスクロール位置で開く。

対処の方針候補（着手時に /review-design で確定させる）:
- 通知に世代（contentUpdateGeneration 相当）や対象 URL を載せ、着地時に一致を確認して捨てる
- あるいは提示中の文書が変わった時点で、それ以前の通知を無効化する

未確認: 実機での再現手順は未取得（レビュー時のコード読みからの指摘）。再現には切替直後に JS からの通知が届く必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 遅れて届いたスクロール位置の通知が、切替先ファイルのキーへ保存されない
- [ ] #2 その振る舞いが破れたら落ちるユニットテストがある
- [ ] #3 対になる saveCurrentScrollPosition 側と、キーの決め方の考え方が揃っている（片方だけ現在値参照が残らない）
<!-- AC:END -->
