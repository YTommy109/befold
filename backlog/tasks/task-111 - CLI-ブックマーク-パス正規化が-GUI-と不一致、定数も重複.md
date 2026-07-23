---
id: TASK-111
title: 'CLI ブックマーク: パス正規化が GUI と不一致、定数も重複'
status: To Do
assignee: []
created_date: '2026-07-23 12:19'
updated_date: '2026-07-23 12:31'
labels:
  - bug
  - cli
dependencies:
  - TASK-115
priority: medium
ordinal: 50500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIBookmarkDefaults は standardizedFileURL.path でパスを正規化するが、GUI の BookmarkStore は resolvingSymlinksInPath().path を使用する。シンボリックリンク経由のパスで CLI と GUI のブックマークが一致しない。また UserDefaults キーとスイート名がハードコードされており BookmarkStore との重複がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI と GUI のパス正規化ロジックが統一されている
- [ ] #2 UserDefaults のキー・スイート名が共有定数化されている
- [ ] #3 シンボリックリンク経由のブックマーク登録・参照テストが存在する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-115(BefoldKit への共通ロジック移設)で解消する方針。
<!-- SECTION:NOTES:END -->
