---
id: TASK-547
title: Edit メニューの構築を分割する（MainMenuBuilder が閾値に近い）
status: To Do
assignee: []
created_date: '2026-08-23 16:34'
labels:
  - refactor
dependencies: []
ordinal: 797000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`scripts/check-type-group-size.sh` の閾値は 400 行（`:29`）。`BefoldApp/befold/App/MainMenuBuilder` グループは **377 行**で、残り 23 行しかない（TASK-485.4 の /review-design 項目 10 で実測）。

TASK-485.4 自体は `DocumentJumpKind.allCases` のループに乗るため増分 0 行だったが、次に Edit / View メニューへ項目を 1 つ足すと超える距離にある。

## 方針

`MainMenuBuilder+ViewMenu.swift` の前例に倣い、Edit メニューの構築を `MainMenuBuilder+EditMenu.swift` へ切り出す。ただし CLAUDE.md が戒めるとおり **extension へ切っても合算行数は減らない**ので、行数だけを目的にしない。責務として「Edit メニューの構成」が独立した関心かを見て判断し、独立していなければ別の受け皿（型の新設）を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 check-type-group-size.sh が exit 0 のまま、MainMenuBuilder グループに余裕ができている
- [ ] #2 分割が行数回避ではなく責務分離になっている理由が Notes にある
- [ ] #3 xcodegen generate 済みで xcodebuild が通る
<!-- AC:END -->
