---
id: TASK-533
title: ダウンロード系指標の内訳が読み取れるようダッシュボードの見せ方を直す
status: To Do
assignee: []
created_date: '2026-08-19 14:52'
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
- [ ] #1 「ダウンロード」ラベルが LP 経由に限定された系列であることが画面から読み取れる
- [ ] #2 lp / sparkle / archive の 3 指標が同一イベントの内訳であることが UI 上で示される（グルーピング、合計の併記など手段は問わない）
- [ ] #3 累計・本日の両方のカード群で同じ見せ方になっている
- [ ] #4 報告された 本日 ダウンロード=1 / 旧バージョン=6 の状態を再現しても、数字が矛盾して見えない
<!-- AC:END -->
