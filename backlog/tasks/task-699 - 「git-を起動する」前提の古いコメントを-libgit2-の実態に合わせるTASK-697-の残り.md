---
id: TASK-699
title: 「git を起動する」前提の古いコメントを libgit2 の実態に合わせる(TASK-697 の残り)
status: To Do
assignee: []
created_date: '2026-10-12 11:54'
labels:
  - tech-debt
dependencies: []
priority: low
ordinal: 888000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-697 は 'git subprocess' の 7 箇所だけを直した。同じ誤解を招く『git ls-files / git rev-parse を起動する』『subprocess』前提の記述が BefoldApp 配下に 30 箇所以上残る(befold/App の GitCommandFileIndex・GitStatusStore・SidebarBaseDirectoryResolver・WorktreeCatalog・RecentRepositoryRecorder・QuickOpenModel ほか、befold/Viewer の FileListModel、BefoldKit の BlockingWork・FileType・TrackedPathResolver、BefoldTestSupport の GitTestRepo ほか)。git 連携は ADR 0006 で libgit2 の in-process 呼び出しへ移行済みで、GitRepository.swift の『外部 git 方式でも…』は意図的な過去形なので対象外。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 rg で『subprocess』『git ls-files』『git rev-parse』『git を起動』を数え、実装の実態と食い違う記述が 0 件になる
- [ ] #2 各コメントの『待たされる理由』を、コードで確かめた実際の理由に直す(確かめられないものは主張を落とす)
<!-- AC:END -->
