---
id: TASK-302
title: performListing の git ステータス適用経路を一本化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 16:35'
updated_date: '2026-08-05 00:45'
labels:
  - git-filter
  - review-finding
  - refactor
dependencies:
  - TASK-299
  - TASK-300
priority: medium
type: task
ordinal: 475000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の PLAUSIBLE 指摘（design-debt）。performListing には git ステータス適用経路が 2 本ある（結合経路＝ガードを自前バンプで無効化して適用／分離経路＝通常の世代ガードで適用。SidebarNavigator.swift:221-237）。この関数の正しさが 3 つの順序機構（listingGeneration、gitStatusGeneration とそれを意図的に破る 225 行目のバンプ、FileListModel.pendingGitStatus の対付け）の相互作用に依存している。

この領域では TASK-291/293/294/296/297 と同型の順序回帰が 5 連続で起きており、「同型の回帰が続いたら設計の欠落を疑う」の条件を満たす。FileListModel.pendingGitStatus が既に提供している「一覧とステータスの原子的な対付け」を絞り込み点として、結合をそこに 1 回だけ持たせる形へ一般化できないか検討する（ADR + 段階移行を含む）。TASK-299/TASK-300 の修正で個別ガードがさらに増える場合、本タスクで吸収する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 git ステータスの適用が単一の経路・単一のガード規約を通る（経路ごとの特例が残らない）
- [x] #2 設計判断が ADR として記録されている
- [x] #3 TASK-291/293/294/296/297 の回帰テストがすべて通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化検討（実装前）
起票時の前提「結合経路がガードを自前バンプで無効化する」は TASK-299 で既に解消済み。現状、両経路（結合/分離）とも同一の
SidebarNavigator.applyGitStatus(_:for:generation:) を通っており、「適用」自体は既に単一関数を経由している。
実態は「関数が2本ある」のではなく、判定に使う状態（発行世代 gitStatusGeneration・反映済み世代 appliedGitStatusGeneration・
FileListModel のディレクトリ対付け entriesDirectory/pendingGitStatus）が SidebarNavigator と FileListModel の2クラスに
分散していること。TASK-294/299の回帰はまさにこの分散（反映可否をSidebarNavigator側だけで判定してからFileListModelの
対付けへ渡す二段構え）が原因。よって単純化の方向は「経路を減らす」ではなく「反映可否の判定状態を1箇所に集約する」。

wait/no-wait（結合/分離）のオーケストレーション分岐自体は、TASK-293（絞り込みON時のちらつき防止）とTASK-297（絞り込み
OFF時のレイテンシ回避）という意図的なUXトレードオフであり、TASK-297 AC#2（ON経路のレイテンシ体感改善、ローディング表示等の
UX判断）は今回のタスクの受け入れ基準に含まれないため統合しない（スコープ外として ADR に明記する）。

## ADR
1. `backlog decision create "git ステータス反映のガードを FileListModel に一本化する"` で decision レコードを作成
2. docs/adr/0003-*.md に Context（5連続回帰の経緯）/Decision（recencyガード+ディレクトリ対付けを1関数に集約、
   wait/no-wait分岐は意図的UXとして温存）/Consequences（TASK-297 AC#2は引き続き未決着・スコープ外）を記録

## 実装
1. FileListModel: applyGitStatus(_:for:) を applyGitStatus(_:for:sequence:) -> Bool へ変更。
   appliedGitStatusSequence を保持し、recencyガード（sequence > appliedGitStatusSequence）とディレクトリ対付けを
   1つの関数内で判定する。invalidatePendingGitStatus(upTo:) を追加（TASK-300のcancelPendingListing相当の一括無効化用）。
2. SidebarNavigator: applyGitStatus(_:for:generation:) から appliedGitStatusGeneration 変数とそのガードを削除し、
   fileListModel への委譲 + 戻り値に応じた gitIndexWatch.update呼び出しに変更。cancelPendingListing() の
   appliedGitStatusGeneration直書きを fileListModel.invalidatePendingGitStatus(upTo:) 呼び出しに置き換える。
3. gitStatusGeneration（発行世代の採番）は SidebarNavigator に残す（複数経路をまたぐ連番の発行元として妥当）。

## 検証
- SidebarNavigatorListingCoherenceTests / SidebarNavigatorGitStatusTests / SidebarNavigatorChangedFilesOnlyTests を実行し
  TASK-291/293/294/296/297/299/300 の回帰テストが全通過することを確認（AC#3）
- swiftformat/swiftlint 差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: FileListModel.applyGitStatus(_:for:) を applyGitStatus(_:for:sequence:) -> Bool へ拡張し、
recency ガード(appliedGitStatusSequence)とディレクトリ対付け(pendingGitStatus)を1関数に集約(ADR 0003)。
SidebarNavigator からは appliedGitStatusGeneration を削除し、gitStatusGeneration は採番のみを担う形に縮小。
cancelPendingListing() は fileListModel.invalidatePendingGitStatus(upTo:) を呼ぶだけになった。

ADR: docs/adr/0003-git-status-guard-in-file-list-model.md / backlog decision-3。
起票時の前提(「結合経路がガードを自前バンプで無効化する」)はTASK-299で既に解消済みだったため、
今回は「経路の削減」ではなく「判定状態(recency+ディレクトリ対付け)の1箇所への集約」を行った。
結合/分離のオーケストレーション分岐(wait/no-wait)は意図的なUXトレードオフ(TASK-293/TASK-297)として
温存し、統合しないことをADRに明記(TASK-297 AC#2は引き続きスコープ外)。

検証:
- swift test --filter "SidebarNavigatorListingCoherenceTests|SidebarNavigatorGitStatusTests|SidebarNavigatorChangedFilesOnlyTests|FileListModelFilterTests|FolderListingViewFilterTests"
  → 47 tests / 5 suites すべて成功(TASK-291/293/294/296/297/299/300の回帰テストを含む)
- swiftformat fix実行 → 差分なし(既に規約準拠)
- swiftlint: origin/main とのベースライン差分ゼロ(diff結果は空)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git ステータス反映の可否判定(recencyガード+ディレクトリ対付け)を SidebarNavigator と FileListModel の2箇所から FileListModel.applyGitStatus(_:for:sequence:) 1関数へ集約した。SidebarNavigator は sequence の採番のみを担う。設計判断は docs/adr/0003-git-status-guard-in-file-list-model.md(decision-3)に記録。結合/分離のオーケストレーション分岐自体は意図的なUXトレードオフのため温存(スコープ外)。TASK-291/293/294/296/297/299/300の既存回帰テストを含む47件のテストが全通過、swiftlintはmainとのベースライン差分ゼロを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
