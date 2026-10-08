---
id: TASK-677
title: 比較基準ラベルがデフォルトブランチを「origin/main」と表示する
status: Done
assignee:
  - '@claude'
created_date: '2026-10-08 05:08'
updated_date: '2026-10-08 05:23'
labels:
  - diff
milestone: m-11
dependencies:
  - TASK-353.2
priority: low
type: bug
ordinal: 866000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-353.1 / 353.2 の実機確認(2026-10-08)で、「スタック全体の変更」のラベルが「origin/main から」になった。デフォルトブランチ名を `origin/HEAD` の指す先から取っており(`GitComparisonBaseResolver.defaultBranch`)、`origin/` 接頭辞付きのまま `GitComparisonResolution.baseBranch` に入るため。TASK-353 の想定は「main から」。

`parentDiffersFromDefault` の比較では `localName(of:)` で接頭辞を落としているが、表示用の名前は落としていない。

## 方針の候補

表示名だけ接頭辞を落とす。merge-base に使う revision は `origin/main` のままにする(ローカルの main が古くても、リモートのデフォルトブランチが基準になるため)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「スタック全体の変更」と縮退時のラベルが「main から」と表示される
- [x] #2 merge-base の計算は従来どおり origin/HEAD の指す先を使う
- [x] #3 テストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化: 既存の localName(of:) を表示名にも使い回した(新状態なし、2 箇所の baseBranch 代入のみ)。merge-base の revision は defaultBranch(origin/main)のまま。テスト: GitParentBranchIntegrationTests.displayNameDropsOriginPrefixButMergeBaseUsesRemote(修正を戻すと baseBranch で 2 件落ちることを確認、baseID は origin 側を維持)。docs/dev/viewer-ui.md に該当記述なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
表示名だけ localName(of:) で origin/ を落とした。
<!-- SECTION:FINAL_SUMMARY:END -->
