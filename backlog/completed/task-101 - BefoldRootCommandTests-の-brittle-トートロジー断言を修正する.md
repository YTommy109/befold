---
id: TASK-101
title: BefoldRootCommandTests の brittle/トートロジー断言を修正する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 13:38'
updated_date: '2026-07-22 14:06'
labels: []
dependencies: []
references:
  - BefoldApp/befoldTests/BefoldRootCommandTests.swift
priority: low
type: chore
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(inselberg-ramada ブランチ)で検出した 2 点。(1) openDiscussionHasEscapingNote の断言が discussion.contains("--") のみで、任意のロングオプション言及で通るトートロジー(この diff 自身が coding_rule.md に追加した「相手側の値を書き換えたらこのテストは落ちるか」の自己チェックに反する)。エスケープ案内に特徴的な文言で断言すべき。(2) rootDiscussionIsConciseAndPointsToOpenHelp の discussion.count < 200 は要件に紐付かないマジック閾値で、正当な 1 文追加でも落ちる。実質的な断言(contains("befold open --help") 等)だけで十分。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 openDiscussionHasEscapingNote が `--` エスケープ案内に特徴的な文言を断言する
- [x] #2 discussion.count < 200 のマジック閾値断言が削除される
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
openDiscussionHasEscapingNote の断言を contains("treat everything after it as paths") に強化。rootDiscussionIsConciseAndPointsToOpenHelp から count < 200 マジック閾値を削除。swift test 全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
