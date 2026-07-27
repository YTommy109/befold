---
id: TASK-161
title: Quick Open の fuzzy 同点タイブレークがソート比較子内で normalizedPathKey（FS I/O）を毎回計算する
status: To Do
assignee: []
created_date: '2026-07-27 05:48'
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
- [ ] #1 matches() のソート比較子がファイルシステムに触れない（保存済みのソートキー文字列の比較になっている）
- [ ] #2 normalizedPathKey の計算が候補1件につき collect 時の1回だけになる
- [ ] #3 既存の QuickOpenCandidatesTests（同点タイブレーク・重複除去）が変更後も通る
<!-- AC:END -->
