---
id: TASK-533
title: ダウンロード系指標の内訳が読み取れるようダッシュボードの見せ方を直す
status: Done
assignee: []
created_date: '2026-08-19 14:52'
updated_date: '2026-08-19 15:09'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 771000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトの管理ダッシュボードで、本日（JST 0 時から）の「ダウンロード」が 1、「旧バージョンのダウンロード」が 6 と表示され、部分集合のはずの数字が本体を上回っているように見える、という報告があった。

調査の結果、数字自体は正しい。3 つの指標は kind='download' を source で分割した互いに素な系列である（site/src/analytics.ts:56-66）。

- ダウンロード = source 'lp'
- 自動アップデート適用 = source 'sparkle'
- 旧バージョンのダウンロード = source 'archive'

期間フィルタも原因ではない。todayTotals は全指標を同一の WHERE timestamp >= jstDayStart(now) を持つ 1 クエリで数えており（site/src/analytics.ts:512-524）、jstDayStart は site/src/lib/jst.ts:33-35 の唯一の定義を通る。ボット除外条件 HUMAN_ONLY も累計・本日で共通（site/src/analytics.ts:449）。

つまり問題は集計ではなく表示にある。「ダウンロード」というラベルが全ダウンロードの合計に読めるため、内訳の 1 つがそれを上回る見た目になる。カードが KIND_LABELS を平坦に並べるだけで（site/src/views/dashboard.tsx:423-425, 440-445）、3 つが同一イベントの内訳であることが UI に現れていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「ダウンロード」ラベルが LP 経由に限定された系列であることが画面から読み取れる
- [x] #2 lp / sparkle / archive の 3 指標が同一イベントの内訳であることが UI 上で示される（グルーピング、合計の併記など手段は問わない）
- [x] #3 累計・本日の両方のカード群で同じ見せ方になっている
- [x] #4 報告された 本日 ダウンロード=1 / 旧バージョン=6 の状態を再現しても、数字が矛盾して見えない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. KIND_LABELS の並びを visit → update_check → download 系 3 つに変え、ラベル接頭辞を「ダウンロード」で揃える
2. DOWNLOAD_METRICS / downloadTotal を METRIC_FILTERS から導いて追加（列挙を手書きしない）
3. dashboard.tsx に metricCards を置き、累計・本日の両方が同じ関数を通るようにする
4. ラベル・並び・合計をテストで固定する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化の検討: 新しい指標や述語（METRIC_FILTERS のエントリ）は増やさなかった。合計は既存の KindCounts から view 側で導く派生値にとどめ、集計クエリ・スキーマは無変更。DOWNLOAD_METRICS は VERSION_BREAKDOWN_METRICS が既に持っていた「kind==='download' で絞る」式をそのまま抜き出したもので、VERSION_BREAKDOWN_METRICS はこれを指すだけになった（同じ式が 2 箇所にあった状態を 1 本に畳んだ）。

ラベル: 「ダウンロード」→「ダウンロード（LP）」、「自動アップデート適用」→「ダウンロード（自動更新）」、「旧バージョンのダウンロード」→「ダウンロード（旧バージョン）」。これらは流入面の内訳表の見出し（'<ラベル>: OS 別' 等）にも出るため、表側の文言も追随している。

担保: 合計カードを消すと落ちるテストと、内訳 3 つの連続を崩すと落ちるテストを置いた。実測で確認済み（metricCards を元の KIND_LABELS.map へ戻すと 2 件失敗）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ダッシュボードのダウンロード系 3 指標を連続配置し、ラベル接頭辞を「ダウンロード」で揃え、直前に内訳の和である「ダウンロード合計」カードを置いた。報告された「本日 ダウンロード 1 / 旧バージョン 6」の状態でも、合計 7 とその内訳として読める。合計は DOWNLOAD_METRICS（METRIC_FILTERS から導出）の和なので、ダウンロード経路を足しても漏れない。検証: site の vitest 369 件すべて green、oxlint --type-aware 0 件、oxfmt 整形ずれなし、tsc --noEmit 通過。
<!-- SECTION:FINAL_SUMMARY:END -->
