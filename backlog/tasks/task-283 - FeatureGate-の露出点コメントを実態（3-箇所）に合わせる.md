---
id: TASK-283
title: FeatureGate の露出点コメントを実態（3 箇所）に合わせる
status: To Do
assignee: []
created_date: '2026-08-04 06:46'
labels: []
dependencies: []
priority: low
ordinal: 473000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowController.swift:9-10 の 'フィーチャーゲートの判定はこの 1 箇所だけ' というコメントは、TASK-264 / TASK-282 で露出点が 3 箇所（makeSidebarGitStatusLoader / makeChangedFilesOnlyToggle / MainMenuBuilder のメニュー項目）に増えたため実態と合わなくなった。

また、このコメントは git 実行全般がゲート下にあるかのように読めるが、実際にゲートされているのは git ステータス系のみで、git rev-parse（基準ディレクトリ解決）・git ls-files（Quick Open）・git worktree list（WorktreeCatalog）・最近使ったリポジトリは stable でも常時稼働する（2026-08-04 に実測）。これらは公開済み機能であり、ゲートを足すべきという指摘ではない。コメントが誤読を招く点だけを直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 露出点が 3 箇所であることと、それぞれの場所がコメントから辿れる
- [ ] #2 ゲート対象が git ステータス系に限られ、git 実行全般ではないことがコメントから読み取れる
- [ ] #3 TASK-187（ゲート解除）で消すべき箇所が漏れなく分かる
<!-- AC:END -->
