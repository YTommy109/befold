---
id: TASK-161
title: Quick Open の fuzzy 同点タイブレークがソート比較子内で normalizedPathKey（FS I/O）を毎回計算する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 05:48'
updated_date: '2026-07-27 06:21'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 236000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QuickOpenCandidateSet.matches(query:limit:) の同点タイブレークが lhs.candidate.url.normalizedPathKey < rhs.candidate.url.normalizedPathKey で、normalizedPathKey は resolvingSymlinksInPath()（パス構成要素ぶんの lstat 系 FS I/O）を呼ぶ。fuzzy スコアは粗い加点の和で同点が大量に発生しやすく、候補上限10,000件・キーストロークごとの呼び出しで比較子内 I/O が高頻度に走る。

これは同じ PR で追加した SuffixPathIndex のクラスコメント（「照合のたびに、しかも比較子の内側で計算すると参照数×候補数のオーダーで正規化が走り、大きなリポジトリでは描画がフリーズする」）が明示的に警告しているアンチパターンそのもの。

collect() は重複除去のため既に全候補で url.normalizedPathKey を計算している（QuickOpenCandidates.swift:117）ので、その値を QuickOpenCandidate に保持して比較子では保存済み文字列を比較する形にする。

該当: BefoldApp/BefoldKit/QuickOpenCandidates.swift:51-55,117
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 matches() のソート比較子がファイルシステムに触れない（保存済みのソートキー文字列の比較になっている）
- [x] #2 normalizedPathKey の計算が候補1件につき collect 時の1回だけになる
- [x] #3 既存の QuickOpenCandidatesTests（同点タイブレーク・重複除去）が変更後も通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
QuickOpenCandidate に sortKey(String) を追加し、collect の重複除去(url.normalizedPathKey)で得た値をそのまま持たせて二重計算を排除。matches() の比較子は sortKey 文字列比較のみで FS I/O を持たない。init は sortKey 省略時 url.normalizedPathKey を既定計算するため既存呼び出し(QuickOpenModel/tests)は無改修。新規テスト2本(比較子が url を見ない/collect が事前計算)追加、swift test 全732パス、lint クリーン。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
matches() の同点タイブレークが比較子内で url.normalizedPathKey(resolvingSymlinksInPath の FS I/O)を毎回計算していた問題を、collect の重複除去で既に計算するキーを QuickOpenCandidate.sortKey に保持し比較子で読むだけにして解消。tiebreakUsesPrecomputedSortKey/collectPrecomputesSortKey で固定、既存タイブレーク・重複除去テストも通過。
<!-- SECTION:FINAL_SUMMARY:END -->
