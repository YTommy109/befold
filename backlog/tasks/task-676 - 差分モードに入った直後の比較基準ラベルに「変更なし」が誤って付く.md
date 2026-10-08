---
id: TASK-676
title: 差分モードに入った直後の比較基準ラベルに「(変更なし)」が誤って付く
status: Done
assignee:
  - '@claude'
created_date: '2026-10-08 05:08'
updated_date: '2026-10-08 05:19'
labels:
  - diff
milestone: m-11
dependencies:
  - TASK-353.2
priority: medium
type: bug
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-353.2 の GUI 実測(2026-10-08、System Events の AX)で、差分モードへ入った直後の最初の 1 回だけ、基準ラベルが「<基準> から (変更なし)」になった。基準を切り替えると「(変更なし)」は消える。変更のあるファイルでも出るため、事実と合わない。3 回の実測すべてで再現した(a.md / b.md / SidebarChangedFilesOnlyIntegrationTests.swift)。

ラベルの『(変更なし)』は `showsDiff && diffContent == .unavailable` から導出している(TASK-353.2 の Plan)。差分取得の完了前に `.unavailable` が見えている可能性があるが、**未調査**。

## 調べること

- 差分モードへ入った直後の `diffContent` の遷移(`.pending` を経由せず `.unavailable` を読んでいないか)
- ラベルの導出が `.pending` を「変更なし」と見なしていないか
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 変更のあるファイルで差分モードへ入った直後に「(変更なし)」が出ない
- [x] #2 差分が実際に空のファイルでは従来どおり「(変更なし)」が出る
- [x] #3 再発を防ぐテストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因(実測): ラベルの『(変更なし)』は diffContent == .unavailable から導出するが、ツールバーの再同期が diffContent の書き換えと切り離されていた。(1) モード切替は applyDisplayMode が先に refreshToolbar し、その時点の diffContent は前回の .unavailable のまま(refresh() が .pending にするのはその後)。(2) 取得の着地(.diff/.unavailable)後にも再同期が走らず、次に別の契機で再同期されるまで古いラベルが残る(基準を切り替えると消えるのはこのため)。.pending を変更なし扱いしているわけではない。単純化: 専用状態は足さず、ViewerDiffPresenter.refresh() が diffContent を書くたびに diffContentDidChange(=refreshUIState)を呼ぶ 1 本の経路に統一。再現テストは修正前に失敗(飛行中と、空差分の着地後の両方)、修正後に通過。docs/dev/viewer-ui.md を更新。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
diffContent 変更のたびにツールバーを再同期する経路を 1 本足した。
<!-- SECTION:FINAL_SUMMARY:END -->
