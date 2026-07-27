---
id: TASK-164
title: Quick Open の文字列照合を Foundation 標準 API と単一の case fold に寄せる
status: To Do
assignee: []
created_date: '2026-07-27 05:49'
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
- [ ] #1 commonPrefix と前方一致が Foundation 標準 API（commonPrefix(with:options:) / range(of:options:)）経由になり、既存の QuickOpenModelTests が通る
- [ ] #2 FuzzyMatcher の大小無視が単一の fold 実装に一本化され、部分列判定と DP が同じ folded 配列を使う
- [ ] #3 FuzzyMatcher.rank が削除または matches との共通コアに統合され、順位付けロジックの二重実装が解消される
- [ ] #4 既存の FuzzyMatcherTests の期待順序（連続一致・単語境界・ファイル名優先・同点安定）が変更後も全て通る
<!-- AC:END -->
