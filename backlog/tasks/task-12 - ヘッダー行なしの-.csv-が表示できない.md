---
id: TASK-12
title: ヘッダー行なしの .csv が表示できない
status: Done
assignee: []
created_date: '2026-07-16 00:54'
updated_date: '2026-07-16 02:09'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/190'
type: bug
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ヘッダー行のない .csv を選択すると「このファイル形式はプレビューに対応していません」と表示される。テキストなので最低でもそのまま表示されるべき。ヘッダー行のない .csv/.tsv はヘッダー行なし状態でレンダリング表示されるべき。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ヘッダー行なしの .csv がテキストとして表示される
- [x] #2 ヘッダー行なしの .csv/.tsv がヘッダーなし状態でテーブルレンダリングされる
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitHub Issue #190 としてクローズ済み（COMPLETED）。別ブランチで修正が完了している。
<!-- SECTION:FINAL_SUMMARY:END -->
