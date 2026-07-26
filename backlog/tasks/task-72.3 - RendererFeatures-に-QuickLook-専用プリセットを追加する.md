---
id: TASK-72.3
title: RendererFeatures に QuickLook 専用プリセットを追加する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 05:16'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
allowDirectHTML/embedImages/allowsInteractiveBridging を全て false にした QuickLook 用の RendererFeatures プリセットを追加し、appex 側の配線を1行にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 RendererFeatures.quickLookRestricted(仮称)が3フラグ全て false である
- [x] #2 quickLookRestricted 使用時に親ディレクトリreadアクセス・postMessageブリッジが無効化されることをテストで確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RendererFeaturesTests に quickLookRestricted の失敗テストを追加する(3フラグ全て false / shouldEnterDirectHTMLMode が false / messageHandlerNames に loadMoreLines・referenceActivated・resolveReferences を含まない)
2. RendererFeatures.quickLookRestricted プリセットを追加する
3. 既存の ViewerRendererOneShotTests がインラインで組み立てている同値の RendererFeatures をプリセット呼び出しに置き換える(二重管理の解消)
4. swift test で確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RendererFeatures.quickLookRestricted を追加した。あわせて、3 つのテストファイルに散っていた同値のインライン RendererFeatures リテラル(計 4 箇所)をプリセット参照へ置き換え、二重管理を解消した。
検証: swift test → 703 tests / 100 suites パス(追加前 697)。新規 RendererFeaturesTests で
- 3 フラグすべて false
- 直接 HTML モードの他条件をすべて満たしても shouldEnterDirectHTMLMode が false(親ディレクトリ read の遮断)
- messageHandlerNames が referenceActivated/loadMoreLines/resolveReferences を含まず 3 件のみ(postMessage ブリッジの遮断)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RendererFeatures.quickLookRestricted プリセットを追加し、既存テストのインライン同値リテラル 4 箇所を置き換えた。新規 RendererFeaturesTests で 3 フラグの値、直接 HTML ロード経路の遮断、インタラクティブなメッセージハンドラ非登録を検証し swift test 703 件パス。
<!-- SECTION:FINAL_SUMMARY:END -->
