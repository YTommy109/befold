---
id: TASK-72.6
title: QuickLook Extension のメモリ・起動速度を実機検証する
status: To Do
assignee: []
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 06:06'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
大きめのmermaid/markdown/巨大コードファイルでappexのメモリ使用量・応答時間を計測する。appexのメモリ上限に対して余裕があるか確認し、必要であればQuickLook専用の追加サイズ上限を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 代表的な大きめファイル種別(mermaid/markdown/巨大コード)でのメモリ・起動速度の計測結果が記録されている
- [ ] #2 appexのメモリ上限に対する余裕があることを確認している、または追加のサイズ上限が導入されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手不可。TASK-72.5 が UTI 競合の設計見直しのため中断しているため、実機検証の対象範囲が確定していない。TASK-72.5 の再開条件(QuickLook 対象 UTI の方針決定)が解消すれば着手できる。
<!-- SECTION:NOTES:END -->
