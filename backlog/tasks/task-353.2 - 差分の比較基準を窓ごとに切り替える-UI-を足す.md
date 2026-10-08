---
id: TASK-353.2
title: 差分の比較基準を窓ごとに切り替える UI を足す
status: To Do
assignee: []
created_date: '2026-10-08 02:00'
labels: []
dependencies:
  - TASK-353.1
parent_task_id: TASK-353
priority: medium
ordinal: 863000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-353 の仕様のうち、差分ビューア側を担う。現状は何との差分かが画面に出ず、基準も変えられない（基準は `GitComparisonBaseResolver` が返す merge-base で固定、`GitDiffReader.diff(forFileAt:in:)` は解決できなければ HEAD へ縮退）。

3 基準（このブランチ／スタック全体／作業中）と、選択肢の出し分け・粒度・永続化しないことは TASK-353 の Description を参照。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 差分モードの間、現在の基準をラベルで表示し、そこから基準を切り替えられる
- [ ] #2 「スタック全体の変更」は、親ブランチがデフォルトブランチと異なるときだけ選択肢に出る
- [ ] #3 基準は窓ごとに独立し、別の窓の基準を変えても影響しない。窓ごとであることが破れたら落ちるテストがある
- [ ] #4 新しい窓は常に「このブランチの変更」から始まる（永続化しない）
- [ ] #5 選んだ基準で差分が空になるファイルでは、差分モードの選択可否が基準に合わせて変わる
- [ ] #6 メニュー・ラベルの文字列が en/ja で揃っている
<!-- AC:END -->
