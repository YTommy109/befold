---
id: TASK-703
title: 'CLI: --check と --bookmark の同時指定を validate で弾く'
status: To Do
assignee: []
created_date: '2026-10-12 13:08'
labels:
  - cli
dependencies: []
priority: low
ordinal: 892000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldCLICommand.validate() は --check と --bookmark の同時指定を弾かず、両方が実行される。意図した組み合わせではなく、終了コードの集約も曖昧になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 --check と --bookmark の同時指定が validate() でエラーになる
- [ ] #2 BefoldCLIOptionValidationTests にケースを追加する
<!-- AC:END -->
