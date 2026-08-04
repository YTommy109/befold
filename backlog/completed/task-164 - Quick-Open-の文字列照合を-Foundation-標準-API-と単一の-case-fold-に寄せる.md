---
id: TASK-164
title: Quick Open の文字列照合を Foundation 標準 API と単一の case fold に寄せる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 05:49'
updated_date: '2026-07-27 06:44'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 239000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
バグの入り込む余地がある自前文字列処理を標準 API へ置き換え、大小無視の実装を一本化する。

(1) QuickOpenModel.commonPrefix(of:): zip(first.lowercased(), name.lowercased()) の文字数で first.prefix(length) を切る自前実装。lowercased で書記素数が変わる文字が混ざると位置がずれる余地がある。Foundation の String.commonPrefix(with:options:.caseInsensitive) は「大小無視で比較し、表記はレシーバ側を採る」というコメントの意図そのものなので、names.dropFirst().reduce(first) { $0.commonPrefix(with: $1, options: .caseInsensitive) } の1行に置き換えられる。

(2) QuickOpenModel.swift:143 の name.lowercased().hasPrefix(fragment) は name.range(of: fragment, options: [.caseInsensitive, .anchored]) != nil が標準形（合成文字・正規化の扱いも Foundation 側に寄る）。

(3) FuzzyMatcher: isSubsequence が1文字比較ごとに String(character).lowercased() を2個生成し（10,000候補×パス長50でキーストロークごとに百万オーダーの割り当て）、直後の bestAlignmentScore は text.map { Character($0.lowercased()) } という別方式の case fold を持つ。fold を1回だけ行い部分列判定と DP の両方で同じ配列を使う形に一本化する。あわせて Character($0.lowercased()) は結果が1書記素でないと trap する初期化子なので、$0.lowercased().first ?? $0 の形に直す。

(4) FuzzyMatcher.rank はプロダクトコードから未使用（呼び出し元はテストのみ）で、QuickOpenCandidateSet.matches が同じ骨格（score→降順→同点昇順→prefix）を origin 加点付きで再実装している。rank を削除してテストを score/matches 経由に直すか、スコア補正クロージャを受ける共通コアへ一般化して matches が委譲する形にする（削除が最小）。

該当: BefoldApp/befold/App/QuickOpenModel.swift:143,150-160 / BefoldApp/BefoldKit/FuzzyMatcher.swift:62-73,93-94,140-149 / BefoldApp/BefoldKit/QuickOpenCandidates.swift:45-57
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 commonPrefix と前方一致が Foundation 標準 API（commonPrefix(with:options:) / range(of:options:)）経由になり、既存の QuickOpenModelTests が通る
- [x] #2 FuzzyMatcher の大小無視が単一の fold 実装に一本化され、部分列判定と DP が同じ folded 配列を使う
- [x] #3 FuzzyMatcher.rank が削除または matches との共通コアに統合され、順位付けロジックの二重実装が解消される
- [x] #4 既存の FuzzyMatcherTests の期待順序（連続一致・単語境界・ファイル名優先・同点安定）が変更後も全て通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
(1) commonPrefix を String.commonPrefix(with:options:.caseInsensitive) の reduce 1 行に、前方一致を range(of:options:[.caseInsensitive,.anchored]) に置換(空断片は range(of:"")が nil のため fragment.isEmpty で明示)。(2) FuzzyMatcher に caseFolded を新設し query/text の fold を1回に集約、isSubsequence と DP が同じ folded 配列を使用。Character($0.lowercased()) の trap を $0.lowercased().first ?? $0 に修正。(3) 未使用の rank と、それだけが使っていた FuzzyMatch 構造体を削除(順位付けは matches に一本化)。テストの rankedTexts ヘルパーを score 経由のローカル実装に置換。swift test 全736パス、lint クリーン。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Quick Open の自前文字列処理を標準 API と単一 case fold に整理。commonPrefix/前方一致を Foundation の commonPrefix(with:options:)/range(of:options:) へ、FuzzyMatcher の大小無視を caseFolded 1 箇所へ集約(部分列判定と DP が共有、trap する Character 初期化子も除去)、未使用 rank と FuzzyMatch を削除し順位付けを matches に一本化。FuzzyMatcherTests/QuickOpenModelTests で期待順序を固定、全736パス。
<!-- SECTION:FINAL_SUMMARY:END -->
