---
id: TASK-153
title: 'パーセントエスケープした # を含む href が fragment として切り落とされる'
status: Done
assignee: []
created_date: '2026-07-25 11:32'
updated_date: '2026-07-25 12:30'
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
- [x] #1 fragment 除去をパーセントデコードより先に行い、`file%23name.md` のようなファイル名が正しく解決される
- [x] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. classify(href:) で #fragment 除去をパーセントデコードより前に移す（生の href の # だけを区切りとして扱う）
2. 行番号サフィックス除去はデコード後のまま維持する（file.md%3A12 の既存挙動を変えない）
3. ReferenceResolverTests のパラメタライズに file%23name.md のケースを追加し、修正前に落ちることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
classify(href:) の順序を「デコード → fragment 除去」から「fragment 除去 → デコード」へ入れ替えた。fragment の区切りは生の href の # だけで判断される。行番号サフィックス (:数字) の除去はデコード後のままにしてある（file.md%3A12 の既存挙動を変えないため）。
実効性の確認: ReferenceResolver.swift だけを git stash して実行し、追加した 2 ケース（./file%23name.md、./file%23name.md#usage）がいずれも /Users/test/docs/file に切り落とされて落ちることを確認済み。
検証: swift test 689 tests（Integration 含む）全パス。途中、pathString の分岐が withoutFragment を参照したままでパーセントデコードが効かなくなる取りこぼしがあり、既存テスト（ReferenceResolverTests の日本語ファイル名、MarkdownImageEmbedderTests のスペース入りファイル名）が検知した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
fragment 除去をパーセントデコードより前に移し、ファイル名の # をエスケープした href（file%23name.md）が切り落とされる問題を修正した。エスケープ # のみ・エスケープ # + 本物の fragment の 2 ケースを回帰テストに追加し、修正前に落ちることを stash 実験で確認済み。swift test 689 件全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
