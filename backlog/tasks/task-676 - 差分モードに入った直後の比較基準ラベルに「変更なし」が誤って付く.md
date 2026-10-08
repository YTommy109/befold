---
id: TASK-676
title: 差分モードに入った直後の比較基準ラベルに「(変更なし)」が誤って付く
status: To Do
assignee: []
created_date: '2026-10-08 05:08'
labels:
  - diff
milestone: m-11
dependencies:
  - TASK-353.2
priority: medium
type: bug
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-353.2 の GUI 実測(2026-10-08、System Events の AX)で、差分モードへ入った直後の最初の 1 回だけ、基準ラベルが「<基準> から (変更なし)」になった。基準を切り替えると「(変更なし)」は消える。変更のあるファイルでも出るため、事実と合わない。3 回の実測すべてで再現した(a.md / b.md / SidebarChangedFilesOnlyIntegrationTests.swift)。

ラベルの『(変更なし)』は `showsDiff && diffContent == .unavailable` から導出している(TASK-353.2 の Plan)。差分取得の完了前に `.unavailable` が見えている可能性があるが、**未調査**。

## 調べること

- 差分モードへ入った直後の `diffContent` の遷移(`.pending` を経由せず `.unavailable` を読んでいないか)
- ラベルの導出が `.pending` を「変更なし」と見なしていないか
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 変更のあるファイルで差分モードへ入った直後に「(変更なし)」が出ない
- [ ] #2 差分が実際に空のファイルでは従来どおり「(変更なし)」が出る
- [ ] #3 再発を防ぐテストがあり、修正を戻すと落ちる
<!-- AC:END -->
