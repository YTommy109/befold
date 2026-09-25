---
id: TASK-485.26
title: 統合バーのジャンプ種別を見出し・定義・変更ブロックの排他にする
status: To Do
assignee: []
created_date: '2026-09-25 07:44'
labels: []
dependencies: []
parent_task_id: TASK-485
type: bug
ordinal: 827000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
統合バーの右上の選択肢は常に「検索」と「ジャンプ 3 種のどれか 1 つ」の 2 つにする。見出しは Markdown（レンダリング・ソース）、定義は対応言語のソース表示、変更ブロックは差分表示の担当。現状は ViewerCapabilities.canJump(to: .heading) が表示モードに依らず true で、差分表示中は見出し+変更ブロック、Swift 等のソース表示中は見出し+定義が同時に出る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 差分表示中は変更ブロックだけが選べ、見出し・定義は選べない
- [ ] #2 定義ジャンプ対応言語のソース表示中は定義だけが選べ、見出しは選べない
- [ ] #3 それ以外の表示では見出しだけが選べる
- [ ] #4 どの表示でもジャンプ種別がちょうど 1 つになることをユニットテストで担保する
<!-- AC:END -->
