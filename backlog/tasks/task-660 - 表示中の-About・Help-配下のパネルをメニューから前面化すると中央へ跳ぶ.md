---
id: TASK-660
title: 表示中の About・Help 配下のパネルをメニューから前面化すると中央へ跳ぶ
status: To Do
assignee: []
created_date: '2026-09-28 06:30'
labels:
  - bug
  - ui
dependencies: []
priority: low
type: bug
ordinal: 860000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-656 の実装後レビュー（/code-review high）の指摘。TASK-656 以前からある挙動で、TASK-656 の回帰ではない。

読むだけのパネル（About・機能概要・キーボードショートカット・AI 連携・OSS ライセンス）は、`HostedPanelWindowController.showAndActivate()` の呼び出しのたびに `center()` される。`toggle()` は最前面でなければ `showAndActivate()` を呼ぶので、表示中だが key でない窓を前面化するときも中央へ動く。

再現手順（想定）: Help > キーボードショートカットを開き、ビューアの窓の横へ動かす。ビューアの窓をクリックする（パネルは表示されたまま key を失う）。もう一度 Help > キーボードショートカットを選ぶと、パネルが画面中央へ跳ぶ。

TASK-656 で決めた「読むだけのパネルは毎回中央」の意図は、閉じていた窓を開くときの位置であって、表示中の窓を前面化するときに動かすことではない。

## 未確認
上の再現手順は実機で確かめていない（コードの経路から導いたもの）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 表示中の読むだけのパネルをメニューから前面化しても、位置が変わらない
- [ ] #2 閉じていた読むだけのパネルを開くと、従来どおり中央に開く
- [ ] #3 前面化で位置が変わらないことを確かめるテストがある
<!-- AC:END -->
