---
id: TASK-171
title: Quick Open のハイライト表示がスコアリングに使われたマッチと不一致になりうる
status: To Do
assignee: []
created_date: '2026-07-27 11:38'
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
- [ ] #1 Quick Open で単語境界に一致する連続した部分文字列が存在する候補では、その連続した部分文字列がハイライトされる
- [ ] #2 スコアリングで採用されたマッチ位置とハイライト表示のマッチ位置が一致する(または、一致しない場合の許容理由が明文化されている)
- [ ] #3 既存のfuzzy検索の順位付け(スコアリング)結果には影響を与えない
<!-- AC:END -->
