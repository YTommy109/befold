---
id: TASK-72.2
title: FileType に QuickLook 対象拡張子集合を追加する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 05:16'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileType.swift の既存分類(レンダリング5種+codeExtensionLanguages)から、PDF・画像を除いた QuickLook 対象拡張子集合を返す純粋関数を追加する。FileType の分類ロジックを単一情報源とし、QuickLook側で独自に拡張子リストを持たないようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 quickLookSupportedExtensions(仮称)が .mmd/.mermaid, .md/.markdown, .svg, .html/.htm, .csv/.tsv, および codeExtensionLanguages の全拡張子を返す
- [x] #2 quickLookSupportedExtensions が pdf/png/jpg/jpeg/gif/webp/bmp/ico を含まない
- [x] #3 拡張子集合を検証するユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化検討
拡張子リストを新たに列挙するのではなく、既存の単一情報源 typeByExtension を
`!isBinaryContent` でフィルタして導出する。isBinaryContent は .image/.pdf のみ
true(FileType.swift:148-153)であり、除外したい「画像・PDF」と完全に一致する。
これにより拡張子の二重管理が生じず、将来 codeExtensionLanguages に追加された
拡張子も自動的に対象へ入る。

## 手順
1. FileTypeTests に quickLookSupportedExtensions の失敗テストを追加する
   - レンダリング5種 + codeExtensionLanguages の全拡張子を含む
   - pdf/png/jpg/jpeg/gif/webp/bmp/ico を含まない
   - allExtensions から画像・PDF 拡張子だけを引いた集合と一致する(導出の同値性)
2. FileType に quickLookSupportedExtensions を追加する
3. swift test で確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
拡張子リストを列挙せず、単一情報源 typeByExtension を `!isBinaryContent` でフィルタして導出した(FileType.swift)。isBinaryContent は .image/.pdf のみ true のため、除外したい画像・PDF と完全一致する。
検証: swift test --filter FileTypeTests → 13 tests パス。うち
- quickLookSupportedExtensionsCoverRenderingAndCodeTypes: レンダリング5種+codeExtensions を包含
- quickLookSupportedExtensionsExcludeBinaryTypes: pdf/png/jpg/jpeg/gif/webp/bmp/ico の 8 ケースすべて非含有
- quickLookSupportedExtensionsAreDerivedFromAllExtensions: allExtensions から画像・PDF を引いた集合と一致(二重管理の混入を検知)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileType.quickLookSupportedExtensions を追加した。独自の拡張子リストを持たず typeByExtension を !isBinaryContent でフィルタする導出とし、拡張子の二重管理を避けた。FileTypeTests に 3 種のテスト(包含・除外・導出の同値性)を追加し swift test でパスを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
