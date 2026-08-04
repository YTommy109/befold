---
id: TASK-171
title: Quick Open のハイライト表示がスコアリングに使われたマッチと不一致になりうる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 11:38'
updated_date: '2026-07-27 13:42'
labels: []
dependencies: []
ordinal: 246000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Quick Open (Cmd+P) の fuzzy 検索で、例えば "default" と入力すると IsolatedDefaults.swift のような候補で本来は連続した単語一致(Default)が見つかるはずだが、実際のハイライト表示は Isolated と Defaults に離散的にまたがった文字にマッチしているように見えるケースが報告された。

BefoldKit/FuzzyMatcher.swift を調査した結果、スコアリング(順位付け)とハイライト表示(候補行にどの文字を強調するか)が別々のアルゴリズムで実装されていることが分かった。

- スコア計算 bestAlignmentScore(foldedQuery:text:) は DP で全アライメントを探索し、連続一致ボーナス(consecutiveBonus)・単語境界ボーナス(boundaryBonus)・ファイル名内一致ボーナス(filenameBonus)により、連続した単語一致を強く優遇するよう設計されている。
- 一方、ハイライト表示に使われる matchedIndices(query:text:) は左から貪欲に1文字ずつ拾うだけの別のサブシーケンス探索で、連続性や単語境界を考慮しない。

このため、スコアリングでは単語一致が高スコアで選ばれていても、画面上のハイライトはスコアリングで実際に使われたアライメントとは無関係な、貪欲マッチによる離散的な文字位置を表示してしまう可能性がある。

まず、既存の bestAlignmentScore の DP が採用した最適アライメント(マッチ位置)をそのままハイライト表示に再利用できないか(matchedIndices という別関数を新設・維持する代わりに)を優先的に検討する。それで不可能な場合のみ、matchedIndices 側にも同等の優先度付けロジックを追加する方針を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Quick Open で単語境界に一致する連続した部分文字列が存在する候補では、その連続した部分文字列がハイライトされる
- [x] #2 スコアリングで採用されたマッチ位置とハイライト表示のマッチ位置が一致する(または、一致しない場合の許容理由が明文化されている)
- [x] #3 既存のfuzzy検索の順位付け(スコアリング)結果には影響を与えない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FuzzyMatcher の DP(bestAlignmentScore)にバックポインタを追加し、最適アライメントのマッチ位置集合を再構成できるようにする(bestAlignment→{score,indices})
2. score() と matchedIndices() を同一の bestAlignment/filenameAlignment 経由に統一し、貪欲な greedySubsequenceIndices を廃止する
3. ハイライト位置=スコアリング採用位置になることをテストで固定(default→Defaults 連続一致 等)
4. 既存スコア順位が不変であることを回帰テストで確認、swift test でグリーン
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
matchedIndices の貪欲サブシーケンス実装(greedySubsequenceIndices)を廃止し、スコアリングの DP(bestAlignment)にバックポインタ(parent 表 + prefixMaximum の argmax)を追加。score()/matchedIndices() を共通の bestAlignment/filenameAlignment 経由に統一したため、ハイライト位置は構造的にスコアリング採用アライメントと必ず一致する。未使用化した maximum ヘルパーも削除。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Quick Open のハイライトがスコアリングと別の貪欲マッチで離散的にズレる問題を、DP アライメントの再利用で解消。FuzzyMatcher の bestAlignmentScore を bestAlignment に拡張してバックポインタで採用位置を復元し、matchedIndices を同じ経路へ統一(貪欲実装を削除)。回帰テスト 'default→IsolatedDefaults.swift で連続 Default(8..14) を強調' を追加し、既存の順位付けテスト含む FuzzyMatcherTests 19件および全 743件のスイートがグリーンであることを swift test で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
