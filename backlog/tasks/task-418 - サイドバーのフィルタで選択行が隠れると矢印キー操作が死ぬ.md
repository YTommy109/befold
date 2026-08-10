---
id: TASK-418
title: サイドバーのフィルタで選択行が隠れると矢印キー操作が死ぬ
status: To Do
assignee: []
created_date: '2026-08-10 07:28'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 507400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListView.selectNext / selectPrevious（FileListView.swift:346 付近）は `guard let current = model.selection, let index = visibleEntries.firstIndex(where: { $0.id == current }) ...` で始まり、フォールバックは model.selection == nil のときしか発火しない。

FileListFilter.apply は presentedPathKey を git フィルタのときだけ残し filterText では残さないため、開いているファイルに一致しないパターンを入力すると選択行が visibleEntries から落ちる。この状態で ↓ / j を押すと firstIndex が nil を返してガードが失敗し、フォールバックにも入らず .ignored を返す。selectPrevious も同じ。マウスで行をクリックするまでキーボードで絞り込み結果へ到達できない。

あわせて visibleEntries の再計算コストも同じ箇所にある。FileListModel.visibleEntries（:269）は listFilter.apply を毎回走らせ（filterText 非空または git フィルタ ON なら 1 件ごとに WildcardMatcher）、entryList が body 1 回につき 2 回（List :161 とオーバーレイ :181）、selectNext が 1 打鍵につき 3 回、selectPrevious が 3 回、enterSelected が 2 回評価する。数千件のディレクトリでフィルタ欄を開いていると矢印キー 1 回でメインアクタ上のフィルタが 5 回以上走る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フィルタで選択行が隠れている状態でも ↓ / ↑ / j / k で絞り込み結果の先頭（または末尾）へ移動できる
- [ ] #2 フィルタをクリアしたときの選択位置が破綻しない
- [ ] #3 1 回のキー操作あたり visibleEntries の評価が 1 回になる
- [ ] #4 キーボード操作のユニットテストを追加する（選択が visibleEntries 外のケースを含む）
<!-- AC:END -->
