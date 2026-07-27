---
id: TASK-169
title: Quick Open の候補リストが絞り込みで画面更新されない(行の id 競合)
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 10:38'
updated_date: '2026-07-27 11:24'
labels:
  - quick-open
  - bug
  - ui
dependencies: []
priority: high
type: bug
ordinal: 244000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cmd+P でファイル名をタイプしても候補リストが最初の一覧のまま更新されない(ユーザー報告・実機再現)。TASK-166 で疑った queryText の didSet/setter は無関係で、モデルは正しく絞り込んでいた(NSLog で candidates=50, 先頭 beta.md 等を確認)。二分探索の結果、resultList を単純な Text に差し替えると更新される一方、ForEach のリストだけが固まることが判明。

## 原因
QuickOpenView.resultList の ForEach:
  ForEach(Array(model.candidates.enumerated()), id: \.element.url) { index, candidate in
      row(...).id(index)
  }
ForEach の identity は候補 URL なのに、各行に .id(index)(位置 index)の別 identity を付けていた。絞り込みで候補が入れ替わっても位置 index は 0,1,2... のままなので、SwiftUI が同じ行ビューを使い回して内容(candidate)を更新せず、リストが固まる。TASK-166 の『絞り込まれない』症状の真因。

## 対応
行の .id を候補 URL(.id(candidate.url))に揃え、ForEach の identity と一致させる。scrollTo も index ではなく candidates[index].url を対象にする。

## 該当
BefoldApp/befold/App/QuickOpenView.swift(resultList の ForEach と onChange)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ファイル名をタイプすると候補リストが実際に画面上で絞り込まれる(実機で確認。例: 'beta'→beta.md が先頭)
- [x] #2 行の identity が ForEach の identity(候補 URL)と一致し、位置 index による別 id を付けていない
- [x] #3 選択移動時の scrollTo が引き続き機能する(選択行が隠れない)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実機確認(System Events + screencapture): query 'beta' でリスト先頭が beta.md(doc アイコン・選択)、続けて task134.mmd/ok.md 等の fuzzy 一致に更新されることを確認。二分探索で resultList を Text('count=… first=…')に差し替えると 'count=50 first=beta.md' と更新される一方、ForEach 行は alpha.md のまま固まることから ForEach の id 競合を特定。全736テスト+lint通過。AC#3(scrollTo)はコードで url ベースへ移行済み、選択移動の手動確認は要フォロー。

AC#3 実機確認(xcodebuild + System Events): Quick Open で Down 15-25回/Up 40回の選択移動後もscreencapture上で選択行(ok.md/AGENTS.md等)が常に表示範囲内に留まることを確認。scrollToが双方向で正常動作。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ForEach 行の .id(index) を .id(candidate.url) に統一し、候補入れ替え時にSwiftUIが行を再利用して固まる不具合を修正済み(実装は既存コミットb969a2b0)。今回AC#3(選択移動時のscrollTo)を実機GUIテストで検証し完了。
<!-- SECTION:FINAL_SUMMARY:END -->
