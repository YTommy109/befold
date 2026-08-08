---
id: TASK-342
title: GitDiffLoader の doc コメントが移動済みテストの旧位置を指している問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 05:35'
updated_date: '2026-08-06 06:46'
labels: []
dependencies: []
priority: low
type: docs
ordinal: 608000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。

GitDiffLoader.swift:21-22 の doc コメントは「ここを破ると ViewerWindowControllerDiffTests.openViewerSharesDiffLoader が落ちる」と書くが、当該テストは ViewerWindowManagerDiffTests.swift:89 に移動済みで、ViewerWindowControllerDiffTests には存在しない（rg で確認済み）。「決めたことには破れたら落ちるものを付ける」規約のポインタが、同じブランチ内で死んでいる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 doc コメントが実在するテスト（ViewerWindowManagerDiffTests.openViewerSharesDiffLoader）を指す
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitDiffLoader.swift の doc コメントの参照先を、実在する ViewerWindowManagerDiffTests.openViewerSharesDiffLoader へ修正した(同テストが green であることを swift test で確認)。
<!-- SECTION:FINAL_SUMMARY:END -->
