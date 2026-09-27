---
id: TASK-655
title: collapseFolder が同期で組み直すため、予約済みの scheduleRebuild と重なると全行の組み立てが 2 回走る
status: Done
assignee: []
created_date: '2026-09-27 08:37'
updated_date: '2026-09-27 09:50'
labels: []
dependencies:
  - TASK-649
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
priority: low
ordinal: 855000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。コードで裏を取った。

## 現状（検証済み）

- `collapseFolder` は `expansion.collapse` の後に `rebuildRows()` を同期で呼ぶ。
- 子リストの着地は `scheduleRebuild()` で次のメインアクター実行へまとめる（`pendingRebuild`）。
- 両方が重なると（レビュー表示で 400 フォルダーの着地が続く間に利用者が 1 つ畳む）、同期の組み直し（700 行で約 12ms）と予約済みの同一の組み直しが続けて走る。

## 方向

組み直しの経路を 1 本にする。`collapseFolder` も `scheduleRebuild()` を使う（畳みが 1 実行遅れる）か、同期で組む前に `pendingRebuild` を捨てる。どちらでも「組み直しは pendingRebuild 経由だけ」か「同期の組み直しは予約を消す」のどちらかを不変条件として doc に書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 組み直しの予約中に `collapseFolder` を呼んでも、`applyRows` が 1 回しか走らないテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化の検討: collapseFolder だけを手当てせず、同期の組み直しの唯一の入口 applyRows の冒頭で予約済みの組み直しを捨てる（最新の材料で組むので予約は用済み）。畳み・ルートの一覧の着地の両方に効く。invalidateExpansion の取り消しと共通のヘルパー dropPendingRebuild へまとめる。不変条件は pendingRebuild と applyRows の doc に書く。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 実装: applyRows 冒頭で dropPendingRebuild()。invalidateExpansion も同ヘルパーを使う。
- テスト collapseDropsScheduledRebuild: 予約中に畳んだ後 hasPendingRebuild が偽（= 同期の 1 回で済み、予約は走らない）。修正前のコードで 5/5 失敗、修正後 15/15 通過。予約の観測は着地ジョブと予約ジョブの実行順に依存するので、観測前に予約が走ったら畳んでやり直す形にした。
- 既存の flaky（別件・未起票）: invalidateDropsScheduledRebuild の try #require(presenter.hasPendingRebuild) が同じ理由で時々落ちる。修正前のコードで 1/20、修正後 2/20（スイート単位の実行で測定）。
- 検証: swift test --filter 'Sidebar|FileList|ViewerWindow' 595 件 pass。swiftlint 0 件。仕様文書は内部の組み直し経路の話で更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
applyRows（同期の組み直しの唯一の入口）の冒頭で予約済みの組み直しを捨てるようにし、畳みやルートの一覧の着地と予約が重なっても全行の組み立てが 1 回で済むようにした。修正前に 5/5 で落ちるテストを追加。
<!-- SECTION:FINAL_SUMMARY:END -->
