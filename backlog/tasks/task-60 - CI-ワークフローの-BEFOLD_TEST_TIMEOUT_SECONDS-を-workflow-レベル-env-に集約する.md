---
id: TASK-60
title: CI ワークフローの BEFOLD_TEST_TIMEOUT_SECONDS を workflow レベル env に集約する
status: To Do
assignee: []
created_date: '2026-07-18 08:14'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
build-and-test（58行目）と thread-sanitizer（110行目）の2つのジョブに BEFOLD_TEST_TIMEOUT_SECONDS: 30 が重複定義されている。値変更時に片方の更新漏れが起こりうる。workflow レベルの env ブロックに移動して一元管理する。
コードレビュー（arch-saguaro ブランチ、2026-07-18）で発見。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BEFOLD_TEST_TIMEOUT_SECONDS が workflow レベルの env ブロックで1箇所のみ定義されている
- [ ] #2 両ジョブ（build-and-test, thread-sanitizer）で環境変数が正しく参照される
<!-- AC:END -->
