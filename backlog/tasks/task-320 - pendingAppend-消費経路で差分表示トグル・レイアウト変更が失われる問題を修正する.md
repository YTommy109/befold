---
id: TASK-320
title: pendingAppend 消費経路で差分表示トグル・レイアウト変更が失われる問題を修正する
status: To Do
assignee: []
created_date: '2026-08-05 16:07'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 504000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

再描画要否の判定は RenderedStateMirror の全体比較（ViewerRenderer+ContentUpdate.swift:214 付近）に置き換えられ diffState も自動的に対象へ入ったが、その手前の pendingAppend 早期リターン経路（ViewerRenderer+ContentUpdate.swift:179-199）が使う canConsumePendingAppend（ViewerRenderer+RenderHelpers.swift:159-168）は diffState を比較していない。このため diffState が変わった updateContent サイクルが applyAppend として消費されると、setDiff / setDiffLayout が JS へ送られず rendered.diffState が古いまま残る。canConsumePendingAppend の showLineNumbers チェックがまさに同型の「トグルが 1 サイクル失われる」穴をガードしており、diffState だけ漏れている。

症状: truncated ファイルで差分表示中に、loadMoreLines のチャンクが pendingAppend に積まれたタイミングで「変更を表示」OFF や Cmd+Ctrl+Shift+J のレイアウト切替を行うと、画面は古い差分/レイアウトのまま、View メニューのチェックだけ新状態になる。次の無関係な再描画イベントまで訂正されない。

修正: canConsumePendingAppend の比較に diffState を追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 pendingAppend が積まれた状態で差分表示トグル・レイアウト切替を行っても、画面が新しい状態に更新される
- [ ] #2 diffState 不変のときのチャンク追記は従来どおり append 経路を通る（全再描画に退化しない）
- [ ] #3 回帰テストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->
