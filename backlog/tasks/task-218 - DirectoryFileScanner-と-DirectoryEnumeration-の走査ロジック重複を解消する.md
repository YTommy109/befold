---
id: TASK-218
title: DirectoryFileScanner と DirectoryEnumeration の走査ロジック重複を解消する
status: To Do
assignee: []
created_date: '2026-07-31 07:43'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/BefoldKit/DirectoryEnumeration.swift
  - BefoldApp/BefoldKit/QuickOpenCandidates.swift
priority: low
ordinal: 298000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-209 でディレクトリ列挙・分類・自然順ソートを BefoldKit の DirectoryEnumeration に単一実装化し、SupportedFileResolver と DirectoryLister が委譲する形にした。一方 Quick Open の候補走査を担う DirectoryFileScanner は別実装として残っており、同種の列挙・隠しファイル判定・フィルタを重ねて持っている可能性がある。TASK-209 着手時点では DirectoryFileScanner が TASK-205（Quick Open 非同期化）の担当領域だったため手を付けていない。両 PR がマージされた後の実態を確認し、実際に重複していれば DirectoryEnumeration に寄せる。重複が見かけ倒しで再帰走査・件数上限など Quick Open 固有の要件が正当な差分であれば、その理由をノートに記録して現状維持とする。着手前に PR #351 (TASK-205) と PR #355 (TASK-209) がマージ済みであることを確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DirectoryFileScanner と DirectoryEnumeration の重複範囲が調査され、統合するか現状維持かの判断根拠がノートに記録されている
- [ ] #2 統合する場合、Quick Open とサイドバー・CLI --check の既存挙動が変わらない（既存テストが通る）
<!-- AC:END -->
