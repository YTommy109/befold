---
id: TASK-324
title: 差分を表示できないファイル種別では git diff を起動しないようにする
status: To Do
assignee: []
created_date: '2026-08-05 16:09'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: low
type: chore
ordinal: 511000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

ViewerWindowController+Diff.swift:18 の refreshDiff は、表示中コンテンツが差分を表示し得る種別かどうか（capabilities.canToggleDiff / showsCodeContent）で絞らずに毎回 git diff を起動する。変更ありのトラッキング済み PNG や PDF を表示していると、コンテンツリロードのたびに描画されることのない diff のためにサブプロセスが起動され、結果は常に破棄される。

修正: refreshDiff の入口で表示種別を判定し、差分を表示できない種別では フェッチをスキップ（かつ diffText をクリア）する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 画像・PDF 表示中のコンテンツリロードで git diff サブプロセスが起動しない
- [ ] #2 差分を表示できる種別（ソースコード等）の挙動は変わらない
<!-- AC:END -->
