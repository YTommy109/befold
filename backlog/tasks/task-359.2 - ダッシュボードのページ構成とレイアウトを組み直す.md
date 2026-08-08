---
id: TASK-359.2
title: ダッシュボードのページ構成とレイアウトを組み直す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 04:55'
updated_date: '2026-08-08 06:42'
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
- [x] #1 全体総数 / 日次総数 / 推移 / 時間帯 / 内訳 が見出し付きのセクションとして分かれている
- [x] #2 各指標のラベルから、集計期間（累計か当日か直近 N 日か）が読み取れる
- [x] #3 期間の切り替えが必要な指標について、切り替え手段が用意されているか、または固定である旨が明示されている
- [x] #4 SSE による #summary 差し替えが新構成でも壊れず、既存の dashboard.test.ts の SSE テストが通る
- [x] #5 ダッシュボードが外部 JS/CSS を読み込まない自己完結 HTML のままである
- [x] #6 JST 化の切替日より前の期間は visitor_day が UTC 日付ハッシュのままで日次ユニークが最大 2 倍に膨らむ。この不連続が画面上に注記として出ている（TASK-359.1 からの申し送り）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. views/dashboard.tsx をセクション構成へ組み直す
   - ヘッダー（#summary の外）: タイトル / SSE 状態 / 「日付・時刻はすべて JST 基準」の明示 / visitor_day の JST 化による不連続の注記。SSE で毎周期送り直さないため差し替え範囲の外に置く
   - #summary の中: 累計 / 本日 (JST) / 推移（直近 14 日・JST）/ 時間帯分布（直近 14 日・JST）/ 内訳（累計）/ 最新イベント の 6 セクションに見出しを付ける
   - 各見出しに集計期間を書き、期間は固定である旨が読み取れるようにする（切り替え UI は作らない = 新しい状態を増やさない）
2. ゼロ埋めにより daily は常に 14 行 / hourly は常に 24 行返るため、既存 CountTable の空状態（rows.length === 0）に入らない。全件 0 のときに『期間内のデータなし』を出す判定を用意する
3. 不連続の注記はデータから判定せず静的テキストにする（切替日の定数を持つとずれても静かに間違うため）
4. 外部 JS/CSS を読み込まない自己完結 HTML の構成は維持する
5. dashboard.test.ts に新構成の検証を足し、既存の SSE テストが通ることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-08 タイムゾーン基準は JST（TASK-359.1 で集計側を JST 化する）。画面上に JST 基準である旨を明示すること。

2026-08-08 実装完了。

構成:
- #summary の中を 6 セクション（累計（全期間）/ 本日（JST 0 時から）/ 日毎の推移（直近 14 日）/ 時間帯分布（直近 14 日・JST）/ 内訳（全期間の累計）/ 最新イベント（直近 20 件））へ分割し、見出しに集計期間を書いた。期間切り替え UI は作らず、固定であることをヘッダーに明示（新しい状態を増やさない判断）。
- JST 基準の明示と visitor_day 不連続の注記は #summary の外（ヘッダー）に置いた。SSE は 2.5 秒ごとに #summary を innerHTML で全置換するため、静的テキストを中に入れると毎周期送り直すことになる。この配置を『注記は SSE の差し替え範囲の外に置く』テストで固定した。
- 不連続の注記はデータから判定せず静的テキストにした。切替日（デプロイ日）を定数で持つと値がずれても静かに間違った表示になるため。
- ゼロ埋めにより daily は常に 14 行 / hourly は常に 24 行返るので、既存 CountTable の空状態（rows.length === 0）には入らない。系列用に SeriesTable を分け、合計 0 のときだけ『期間内のデータなし』を出す。
- 見出しの入れ子が h2 の中に h2 になっていたため CountTable / SeriesTable を h3 にした。
- 外部 JS/CSS を読み込まない自己完結 HTML の構成は維持（STYLE / STREAM_SCRIPT のインライン定数のまま）。

検証: npx vitest run で 70 passed / 6 files（新規 2 件を含む）、npx tsc --noEmit エラーなし。SSE テストは既存のまま通過。
未検証: 実ブラウザでの表示確認（セクション間の余白、grid の折り返し）は未実施。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ダッシュボードを累計 / 本日 / 日毎の推移 / 時間帯分布 / 内訳 / 最新イベントの 6 セクションへ組み直し、各見出しに集計期間を明記した。JST 基準の明示と visitor_day 不連続の注記は、SSE が innerHTML で全置換する #summary の外へ置き、その配置をテストで固定した。ゼロ埋め系列は合計 0 のときだけ空状態を出す SeriesTable に分離。期間切り替え UI は作らず固定である旨を明示した。vitest 70 件 pass、tsc エラーなし。
<!-- SECTION:FINAL_SUMMARY:END -->
