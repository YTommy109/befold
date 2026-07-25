---
id: TASK-153
title: 'パーセントエスケープした # を含む href が fragment として切り落とされる'
status: To Do
assignee: []
created_date: '2026-07-25 11:32'
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
