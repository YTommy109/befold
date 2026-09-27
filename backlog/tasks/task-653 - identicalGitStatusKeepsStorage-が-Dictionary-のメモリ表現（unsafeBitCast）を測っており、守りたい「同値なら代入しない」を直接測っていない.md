---
id: TASK-653
title: >-
  identicalGitStatusKeepsStorage が Dictionary
  のメモリ表現（unsafeBitCast）を測っており、守りたい「同値なら代入しない」を直接測っていない
status: To Do
assignee: []
created_date: '2026-09-27 08:37'
labels: []
dependencies: []
references:
  - BefoldApp/befoldTests/SidebarIdenticalListingTests.swift
  - BefoldApp/befold/Viewer/FileListModel.swift
priority: low
ordinal: 853000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。TASK-646 で足したテスト `identicalGitStatusKeepsStorage` が `unsafeBitCast(Dictionary, to: AnyObject.self)` の `===` で同一ストレージを判定している。

## 現状（検証済み）

- 判定は Darwin の Dictionary が 1 語のストレージ参照であることに依存する。ツールチェーンの表現変更で UB / 無関係な理由で落ちる・通る。`.claude/CLAUDE.md`「環境に依存する実測値をアサートしない … 守りたい値そのものを測る」。
- 守りたい不変条件は「`setGitStatus` は同値なら代入しない」。同じ PR で `FileListModel.gitStatus` の `didSet` が `onGitStatusChange` を呼ぶようになったので、代入の有無は購読者の呼ばれた回数で直接観測できる（代入しない ⇒ didSet が走らない ⇒ ストレージが保たれる）。

## 方向

テストで `model.onGitStatusChange = { count += 1 }` を繋ぎ（precondition は購読者が nil なら通る）、同値の 2 回目の `applyGitStatus` 後も count が 1 のままであることを測る。`unsafeBitCast` は撤去する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `identicalGitStatusKeepsStorage` が `unsafeBitCast` を使わず、`onGitStatusChange` の呼び出し回数で同値の非代入を測っている
<!-- AC:END -->
