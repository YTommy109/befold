---
id: TASK-127
title: CLI と GUI の同時ブックマーク更新で書き込みが失われる
status: To Do
assignee: []
created_date: '2026-07-24 22:22'
labels:
  - cli
  - bug
dependencies: []
priority: medium
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で PLAUSIBLE 判定。befold-cli/BefoldCLICommand.swift:88 で CLI の bookmarkStore は GUI と同じ UserDefaults ドメイン(com.degino.befold)に別プロセスから書き込む。BookmarkStore.add/toggle は BookmarkedPaths 配列全体の非アトミックな read-modify-write のため、CLI の `befold --bookmark a.md` と GUI のブックマーク操作がほぼ同時に走ると、GUI が CLI 追加前の配列を書き戻して追加分を消す(CLI は成功を報告済みなのにブックマークが消えるデータロス)。
対応方針は要検討: 書き込みを GUI プロセスへ転送して一本化する、通知で GUI に再読込させる、等。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI からのブックマーク追加が GUI の同時操作で失われない設計になっている
- [ ] #2 採用した方式の並行性テストまたは設計メモがある
<!-- AC:END -->
