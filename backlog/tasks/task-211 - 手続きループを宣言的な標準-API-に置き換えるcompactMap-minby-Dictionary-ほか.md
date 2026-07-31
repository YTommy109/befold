---
id: TASK-211
title: '手続きループを宣言的な標準 API に置き換える(compactMap/min(by:)/Dictionary ほか)'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:57'
updated_date: '2026-07-31 07:25'
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
- [x] #1 候補箇所が宣言的な標準 API に置き換わり、挙動が変わらない(既存テストが通る)
- [x] #2 可読性が下がる過剰な関数型化(複雑な reduce 等)を持ち込まない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. QuickOpenCandidates.matches を compactMap→sorted→prefix→map に置換(重複除去部は TASK-205 の担当範囲のため触らない)
2. SessionStore.SessionLayout.filtered を compactMap に、noteRenamed の index ループを map に置換
3. SuffixPathIndex.init を Dictionary(grouping:) に、bestMatch を min(by:) に置換
4. TextEncoding.detectBOM を BOM テーブル + first(where:) に置換
5. FileType.typeByExtension を Dictionary(uniqueKeysWithValues:) に置換(重複拡張子は trap で検出)
6. SessionRestorer.currentSessionLayout の 2 本の for を連結シーケンスに
7. DirectoryLister の alphabetical 分岐を sorted 式に
8. swift build / swift test / SwiftLint で挙動不変を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
適用: (1) QuickOpenCandidateSet.matches → compactMap→sorted→prefix→map (2) SessionLayout.filtered → compactMap / SessionStore.noteRenamed → map で新 layout 生成 (3) SuffixPathIndex.init → Dictionary(grouping:) / bestMatch → lazy.filter.map.min(by:) (4) TextEncoding.detectBOM → bomTable + first(where:)(長い BOM を先に置き UTF-32 が UTF-16 に食われないようにする) (5) FileType.typeByExtension → Dictionary(uniqueKeysWithValues:) (7) SessionRestorer.currentSessionLayout → orderedWindows + windows の連結を compactMap (9) DirectoryLister の alphabetical 分岐 → sorted 式。
QuickOpenCandidates の normalizedPathKey 二重計算(重複除去部)は TASK-205 の AC #4 の範囲なので本タスクでは触っていない。
検証: swift build 成功、swift test 905 tests / 125 suites すべて通過、swiftformat --lint で 0 files require formatting。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
手続き的な var 蓄積 + for ループを標準ライブラリの宣言的 API(compactMap / sorted / min(by:) / Dictionary(grouping:) / Dictionary(uniqueKeysWithValues:) / first(where:))へ置き換えた。挙動は不変で、FileType の拡張子対応表は重複登録が実行時 trap で検出されるようになった。複雑な reduce 等の過剰な関数型化は持ち込んでいない。検証は swift build 成功・swift test 905 件全通過・swiftformat --lint 指摘なし。
<!-- SECTION:FINAL_SUMMARY:END -->
