---
id: TASK-359.2
title: ダッシュボードのページ構成とレイアウトを組み直す
status: To Do
assignee: []
created_date: '2026-08-08 04:55'
labels:
  - site
  - analytics
dependencies: []
parent_task_id: TASK-359
priority: high
ordinal: 620000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site/src/views/dashboard.tsx は現在、カード群（全期間総数3枚＋ユニーク訪問者）+ 表 8 枚 + 最新イベント表のフラットな 1 ページ。全体総数エリア / 日次総数エリア / 推移 / 時間帯 / 内訳 という情報の階層が画面に現れていない。期間フィルタ UI も無い。CSS はファイル内インライン定数 STYLE (:32)、JS も STREAM_SCRIPT (:17) のみで外部アセットを読み込まない自己完結 HTML という構成は維持する前提で、セクション分けとレイアウトを組み直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 全体総数 / 日次総数 / 推移 / 時間帯 / 内訳 が見出し付きのセクションとして分かれている
- [ ] #2 各指標のラベルから、集計期間（累計か当日か直近 N 日か）が読み取れる
- [ ] #3 期間の切り替えが必要な指標について、切り替え手段が用意されているか、または固定である旨が明示されている
- [ ] #4 SSE による #summary 差し替えが新構成でも壊れず、既存の dashboard.test.ts の SSE テストが通る
- [ ] #5 ダッシュボードが外部 JS/CSS を読み込まない自己完結 HTML のままである
<!-- AC:END -->
