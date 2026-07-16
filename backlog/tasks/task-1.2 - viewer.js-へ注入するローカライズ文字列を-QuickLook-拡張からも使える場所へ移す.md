---
id: TASK-1.2
title: viewer.js へ注入するローカライズ文字列を QuickLook 拡張からも使える場所へ移す
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-16 03:44'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/210
parent_task_id: TASK-1
priority: medium
ordinal: 11200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #210 から移行。Localizable.xcstrings が app ターゲット側にのみ存在し、viewer.js へ注入する検索バー・バナー文言に QuickLook 拡張から届かない。BefoldKit 側の xcstrings へ移すか、QuickLook 拡張ターゲットに必要キーのみ複製する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer.js/viewer.html へ注入する文言キーが QuickLook 拡張からアクセスできる
<!-- AC:END -->
