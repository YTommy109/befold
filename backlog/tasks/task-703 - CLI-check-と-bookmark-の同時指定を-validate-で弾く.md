---
id: TASK-703
title: 'CLI: --check と --bookmark の同時指定を validate で弾く'
status: Done
assignee: []
created_date: '2026-10-12 13:08'
updated_date: '2026-10-14 07:52'
labels:
  - cli
dependencies: []
priority: medium
type: bug
ordinal: 892000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldCLICommand.validate() は --check と --bookmark の同時指定を弾かず、両方が実行される。意図した組み合わせではなく、終了コードの集約も曖昧になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 --check と --bookmark の同時指定が validate() でエラーになる
- [x] #2 BefoldCLIOptionValidationTests にケースを追加する
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
validate() に check && bookmark の同時指定を弾くガードを追加し、BefoldCLIOptionValidationTests にケースを追加した。swift test --filter BefoldCLIOptionValidationTests で 8 テスト全通過。修正を戻すと新規テストだけが落ちることも確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
