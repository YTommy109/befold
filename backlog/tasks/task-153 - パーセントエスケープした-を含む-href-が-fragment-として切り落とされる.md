---
id: TASK-153
title: 'パーセントエスケープした # を含む href が fragment として切り落とされる'
status: In Progress
assignee: []
created_date: '2026-07-25 11:32'
updated_date: '2026-07-25 12:26'
labels:
  - path-reference
dependencies: []
priority: low
type: bug
ordinal: 229000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ReferenceResolver.swift はパーセントデコード（L42）を fragment 除去（L56-60）より先に行うため、ファイル名のリテラル # をエスケープした href（例: `file%23name.md`）がデコード後に # 以降を fragment として切り落とされ、正しいファイルに解決できない。main 時点からの既存挙動で今回の退行ではないが、classify(href:) への一本化で直しやすくなった（コアレビュー指摘・軽微）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 fragment 除去をパーセントデコードより先に行い、`file%23name.md` のようなファイル名が正しく解決される
- [ ] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. classify(href:) で #fragment 除去をパーセントデコードより前に移す（生の href の # だけを区切りとして扱う）
2. 行番号サフィックス除去はデコード後のまま維持する（file.md%3A12 の既存挙動を変えない）
3. ReferenceResolverTests のパラメタライズに file%23name.md のケースを追加し、修正前に落ちることを確認する
<!-- SECTION:PLAN:END -->
