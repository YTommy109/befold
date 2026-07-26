---
id: TASK-72.7
title: QuickLook Extension のテスト・受け入れ確認を行う
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 14:45'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 217000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileType拡張子集合のユニットテスト、xcodebuildでのappexビルド確認、Finder上でのQuickLook手動検証(対象拡張子のプレビュー表示、PDF/画像が対象外であることを含む)を行い、TASK-72の受け入れ基準を満たすことを確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 xcodebuild で QuickLook Extension ターゲットのビルドが成功する
- [x] #2 Finder上での手動QuickLook検証結果が記録されている
- [x] #3 TASK-72の受け入れ基準が全て満たされている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証結果(2026-07-26 / macOS 26.5.2 / befold 1.7.3(748))

### AC#1 ビルド
xcodebuild build -scheme befold -configuration Release(Developer ID 署名)が成功し、
BefoldQuickLook.appex が Contents/PlugIns に同梱される。
codesign --verify --deep --strict も通る。

### AC#2 Finder 上での手動検証
検証は /Applications の appex 1 つだけを LaunchServices に登録した状態で行う必要がある。
.build や DerivedData のコピーを一度でも起動すると登録を奪われ、別ビルドの結果を
見てしまう(実際に一度そうなり、前半の観測結果を破棄した)。

| 拡張子 | 結果 |
| --- | --- |
| .swift / .json / .py / .yaml | ハイライト表示。バッジあり |
| .tsv | 先頭チャンク表示。バッジあり |
| .mermaid | mermaid 図を描画。独自 UTI に解決されるため競合しない |
| .mmd / .md / .markdown | QLMarkdown を外した状態で描画を確認(.mmd は UTI が net.ia.markdown でも拡張子判定で mermaid として描画される) |
| .svg / .html / .htm / .csv | befold は呼ばれない。macOS の内蔵・アプリレベルのプレビューアが優先される |
| .txt | 対象外(public.plain-text 未宣言)で意図どおり |
| .pdf | 対象外。意図どおり |
| .ts | 呼ばれない(public.mpeg-2-transport-stream に解決され、内蔵プレビューアが優先) |

### .svg / .html / .csv が取られる理由(AC#3 で親 AC#5 を追加した根拠)
登録済み QuickLook プレビュー拡張 22 個の Info.plist を走査したところ、
public.html / public.svg-image / public.comma-separated-values-text を
QLSupportedContentTypes で宣言しているのは befold だけだった。
Safari の SafariQuickLookPreview は QLSupportedContentTypes を持たず、
アプリのドキュメントタイプ経由で public.html を扱う。
つまりこれらは拡張どうしの競合ではなく、内蔵・アプリレベルのプレビューアが
優先される .ts と同種の制約であり、拡張側からは覆せない。

### AC#3 親タスクの受け入れ基準
TASK-72 の AC#1〜#5 をすべて確認済み。#5 は上記の走査結果に基づき、
表示できないことを仕様として明記する形で追加した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
QuickLook Extension のビルド・テスト・Finder 上での受け入れ確認を行った。

xcodebuild(Release / Developer ID)成功、swift test 659 件パス、Finder で全対象拡張子の挙動を確認した。befold が担当するのは .swift/.json/.py/.yaml/.tsv/.mermaid と、競合拡張が無い環境の .mmd/.md/.markdown。

.svg/.html/.htm/.csv は、登録済み QuickLook 拡張 22 個を走査した結果 befold だけが UTI を宣言しているにもかかわらず呼ばれず、macOS の内蔵・アプリレベルのプレビューアが優先される .ts と同種の制約と判明した。拡張側から覆せないため、親タスクに AC#5 として仕様を明記した。

検証時は /Applications の appex 1 つだけを登録した状態にする必要がある(DerivedData のコピーが登録を奪うと別ビルドの結果を見てしまう)。
<!-- SECTION:FINAL_SUMMARY:END -->
