---
id: TASK-297
title: フォルダー移動が毎回 git status の完了を待つようになっている
status: To Do
assignee: []
created_date: '2026-08-04 14:47'
labels:
  - git-filter
  - review-finding
  - performance
dependencies:
  - TASK-294
priority: medium
type: bug
ordinal: 495000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の検証済み指摘（CONFIRMED）。

performListing が onApplied の前に `await gitTask.value` を挟むため、ディレクトリ列挙が終わっても git サブプロセスが返るまで entries が反映されない。git status は絞り込みの ON/OFF に関係なく .always で取得されるため、絞り込みを使っていないユーザーもフォルダー移動・ウィンドウフォーカス復帰（refreshFileList）・ソート変更のたびに待たされる。大きい/コールドなリポジトリでは 1〜2 秒前のディレクトリの内容が表示されたままになる。

該当: BefoldApp/befold/App/SidebarNavigator.swift:214

注: TASK-294 と同じ経路を触るため、対応方針は合わせて検討すること（同時反映を保ちつつ待ち時間を消す設計が要る）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 絞り込み OFF のときフォルダー移動が git status の完了を待たない
- [ ] #2 絞り込み ON でも、一覧と git ステータスの整合（TASK-294）を崩さずに体感レイテンシを改善する
- [ ] #3 レイテンシは固定間隔の負荷合計ではなく、移動から反映までの実測で評価する
<!-- AC:END -->
