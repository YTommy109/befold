---
id: TASK-697
title: 「git subprocess」を前提にした古いコメントを libgit2 の実態に合わせる
status: To Do
assignee: []
created_date: '2026-10-09 13:29'
labels:
  - tech-debt
dependencies: []
priority: low
ordinal: 886000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
git 連携は ADR 0006 で外部 `git` の `Process` 起動から libgit2 の in-process 呼び出しへ移行済みで、本体コードに git を起動する `Process` は無い(`rg "Process\(\)"` では `BefoldCLI/CLIAppLauncher.swift` の `open` とテスト補助のみ)。それでも「git subprocess を伴いうる」という記述がコメントに残り、実装を誤解させる。該当は `rg "git subprocess" BefoldApp` で 7 箇所(ReferenceResolutionCoordinator、ReferenceResolutionQueue、ViewerRenderer、SidebarListingCoordinator、テスト 3 件)。非同期である理由が git 起動でないなら、本当の理由(libgit2 の呼び出しが重い等)を確かめて書き直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `rg "git subprocess" BefoldApp` が 0 件になる
- [ ] #2 各コメントが述べる「待たされる理由」を、コードで確かめた実際の理由に直す(確かめられないものは主張を落とす)
<!-- AC:END -->
