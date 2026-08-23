---
id: TASK-485.25
title: 文書内ジャンプのメニュー項目にキー等価を割り当てる
status: To Do
assignee: []
created_date: '2026-08-23 16:35'
updated_date: '2026-08-23 16:36'
labels:
  - jump
dependencies:
  - TASK-485.16
parent_task_id: TASK-485
ordinal: 799000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`BefoldApp/befold/App/MainMenuBuilder.swift` の `addDocumentJumpItems` の doc コメントが「キー等価はまだ付けない…割り当ては stable 昇格と同時に決める」と申し送っている。理由として挙げられていたのは 2 つ。

1. 空いている ⌃⌘ 系は View メニューが使い切っている（⌃⌘F/G/H/T）。素の ⌘G / ⇧⌘G は検索送りが持っている
2. 紹介サイトのショートカット表を作る `site/src/lib/shortcuts.ts` は開発中機能のゲートを認識しないため、キー等価を付けると stable のユーザーへ存在しない機能を告知することになる

このうち 2 は TASK-485.16（ゲート撤去）が済めば消える。1 は残るので、空きキーの選定が実作業になる。

## 注意

現在ジャンプの種類は 3 つ（見出し / 変更箇所 / 定義）。項目は `DocumentJumpKind.allCases` から生成されるので、キー等価も種類ごとに決める必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 各ジャンプ項目にキー等価が割り当てられ、既存のショートカットと衝突していない
- [ ] #2 site/src/lib/shortcuts.ts と紹介サイトのショートカット表に反映されている
- [ ] #3 MainMenuBuilder の「キー等価を付けない」旨の doc コメントが実態に合わせて更新されている
<!-- AC:END -->
