---
id: TASK-930.9
title: ADR 0013 の Context の現状調査の見出しに調査日を書く
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T13:14:04Z'
updated_date: '2026-11-26T01:44:44Z'
labels: []
dependencies: []
parent_task_id: TASK-930
priority: low
type: chore
ordinal: 871000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘(2026-11-25、nit)。docs/adr/0013-presentation-intent-before-sidebar-sync.md の「### 入口の意図と実際の動作がずれている(コード参照)」は決定前のコードの記述だが調査日が無い。.claude/CLAUDE.md の規定(ADR の Context が現状調査を含むなら見出しに調査日を書く)に反する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 見出しを「入口の意図と実際の動作がずれている(コード参照 / 2026-11-25 時点)」にしている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
指摘の 71 行目に加え、同じく決定前のコードを述べる 64 行目「決定と実装の向きが逆になっている」にも調査日を入れた。両見出しのスラッグへのリンクは docs・backlog/decisions に無い(rg で確認)。markdownlint 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ADR 0013 の Context のうち、決定前のコードを述べる 2 つの見出しに「コード参照 / 2026-11-25 時点」を入れた(.claude/CLAUDE.md の規定)。
<!-- SECTION:FINAL_SUMMARY:END -->
