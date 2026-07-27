---
id: TASK-167
title: Quick Open の候補行で入力に一致した文字を強調表示する
status: To Do
assignee: []
created_date: '2026-07-27 08:36'
updated_date: '2026-07-27 08:36'
labels:
  - quick-open
  - enhancement
  - ui
dependencies:
  - TASK-166
priority: medium
type: enhancement
ordinal: 242000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VSCode の Quick Open のように、候補行でユーザーがタイプした文字と一致した部分の文字色/装飾を変えて強調表示する。現状 QuickOpenView.row はファイル名(lastPathComponent)と displayPath をプレーンな Text で描画しており、どの文字が一致したかが分からない。

## 現状
- QuickOpenView.row は Text(candidate.url.lastPathComponent) と Text(candidate.displayPath) のみ(強調なし)。
- FuzzyMatcher.score は最良対応付けの『スコア』だけを返し、どの位置が一致したか(マッチしたインデックス集合)を返さない。DP(bestAlignmentScore)は最良経路を計算しているが位置を保持していない。
- パスモード(QuickOpenModel.pathCandidates)は前方一致で、先頭断片が一致部分。

## 対応方針
1. FuzzyMatcher に『一致位置(text 内のマッチしたインデックス)』も返す API を追加する(既存 score(query:text:) の順序・スコアは不変に保つ。DP の最良経路をバックトラックして位置集合を得る)。
2. QuickOpenCandidateSet.matches が候補ごとに一致位置を添えて返せるようにする(または QuickOpenView 側で表示文字列に対して再計算する。displayPath と照合対象がずれない設計を保つ)。
3. QuickOpenView.row を AttributedString 化し、一致文字を色(accentColor 等)+ boldで強調する。パスモードは前方一致断片を強調する。
4. 選択行(背景ハイライト)とのコントラストを確認する。

## 該当
BefoldApp/BefoldKit/FuzzyMatcher.swift(score/bestAlignmentScore) / BefoldApp/BefoldKit/QuickOpenCandidates.swift(matches) / BefoldApp/befold/App/QuickOpenView.swift(row)

## 前提
TASK-166(絞り込みが動く)が先に解消していること。絞り込みが動かない状態では強調も体感できない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 候補行で、タイプした文字に一致した部分が色/太字で視覚的に強調される(fuzzy・パスモード両方)
- [ ] #2 FuzzyMatcher が一致位置(インデックス集合)を返す API を持ち、既存 score のスコア値と候補の並び順は不変(既存 FuzzyMatcherTests が通る)
- [ ] #3 一致位置の返却が正しいこと(連続一致・単語境界・飛び飛び一致)をテストで固定する
- [ ] #4 選択行の背景ハイライト下でも強調が読めるコントラストであることを手動確認する
<!-- AC:END -->
