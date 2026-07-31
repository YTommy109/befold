---
id: TASK-211
title: '手続きループを宣言的な標準 API に置き換える(compactMap/min(by:)/Dictionary ほか)'
status: To Do
assignee: []
created_date: '2026-07-31 02:57'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/BefoldKit/QuickOpenCandidates.swift
  - BefoldApp/BefoldKit/SuffixPathMatcher.swift
  - BefoldApp/BefoldKit/TextEncoding.swift
  - BefoldApp/BefoldKit/FileType.swift
  - BefoldApp/befold/App/SessionStore.swift
priority: low
ordinal: 291000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(2026-07-31)で挙がった、var 蓄積 + for ループを標準ライブラリの高階関数で宣言的に書き換えられる箇所の適用。主な候補: (1) QuickOpenCandidates.matches の var 蓄積 → compactMap→sorted→prefix→map パイプライン (2) SessionStore.SessionLayout.filtered → compactMap (3) SuffixPathMatcher.bestMatch の手書き最良値追跡 → min(by:)(コメント自身が min(by:) と同じ結果と明記) (4) TextEncoding.detectBOM の if 羅列 → BOM テーブル + first(where:) (5) FileType.typeByExtension の var 辞書 + 9 本の for → Dictionary(uniqueKeysWithValues:)(重複登録の trap 検出も得られる) (6) SessionStore.noteRenamed の index ループ → map (7) SuffixPathIndex.init → Dictionary(grouping:) (8) SessionRestorer.currentSessionLayout の 2 本の for → 連結シーケンス (9) DirectoryLister の alphabetical 分岐 → sorted 式。ホットパス(StringChunkReader/FuzzyMatcher 等)は性能上の理由が明記されており対象外。TASK-205 が QuickOpenCandidates を先に触る可能性があるため、着手時は重複を確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 候補箇所が宣言的な標準 API に置き換わり、挙動が変わらない(既存テストが通る)
- [ ] #2 可読性が下がる過剰な関数型化(複雑な reduce 等)を持ち込まない
<!-- AC:END -->
