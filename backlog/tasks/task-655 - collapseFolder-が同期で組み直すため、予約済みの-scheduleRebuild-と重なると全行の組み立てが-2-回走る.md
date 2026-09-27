---
id: TASK-655
title: collapseFolder が同期で組み直すため、予約済みの scheduleRebuild と重なると全行の組み立てが 2 回走る
status: To Do
assignee: []
created_date: '2026-09-27 08:37'
updated_date: '2026-09-27 08:37'
labels: []
dependencies:
  - TASK-649
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
priority: low
ordinal: 855000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。コードで裏を取った。

## 現状（検証済み）

- `collapseFolder` は `expansion.collapse` の後に `rebuildRows()` を同期で呼ぶ。
- 子リストの着地は `scheduleRebuild()` で次のメインアクター実行へまとめる（`pendingRebuild`）。
- 両方が重なると（レビュー表示で 400 フォルダーの着地が続く間に利用者が 1 つ畳む）、同期の組み直し（700 行で約 12ms）と予約済みの同一の組み直しが続けて走る。

## 方向

組み直しの経路を 1 本にする。`collapseFolder` も `scheduleRebuild()` を使う（畳みが 1 実行遅れる）か、同期で組む前に `pendingRebuild` を捨てる。どちらでも「組み直しは pendingRebuild 経由だけ」か「同期の組み直しは予約を消す」のどちらかを不変条件として doc に書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 組み直しの予約中に `collapseFolder` を呼んでも、`applyRows` が 1 回しか走らないテストがある
<!-- AC:END -->
