---
id: TASK-392
title: 解析ダッシュボードの集計軸からロボットの巡回を除外する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-09 13:33'
updated_date: '2026-08-10 01:36'
labels: []
dependencies:
  - TASK-386
priority: medium
type: feature
ordinal: 650000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-386 で ua_summary にボット接頭辞 'bot:' が入り、uaSplit（site/src/analytics.ts:254）は人間とロボットを分離して表示するようになった。しかしボット除外が入っているのはこの 1 箇所だけで、日次推移・国別・referrer 別・OS 別といった他の集計はすべてボットを含んだ生の数のままになっている。

このため、ダッシュボードの主要な数字（訪問数の推移など）が実際の人間の訪問より大きく出る。実データを見ながら配布・普及の戦略を検討する用途では、この差が判断を歪める。

実測（2026-08-09 に本番 D1 へ SELECT）: events は 2026-07-29 起点で visit 216 件 / ユニーク 159、update_check 88 件、download 11 件（うち source='sparkle' 2 件、残り 9 件は source 列の導入前で NULL）。source='lp' は 0 件。この visit 216 件はボットを含む生の数。

前提と裏付け:
- コード参照: ボット判定の SQL 表現は site/src/analytics.ts:251 の BOT_MATCH（ua_summary LIKE 'bot:%'）。これを使っているのは uaSplit（同 254）のみで、他の 'FROM events' を含む集計（同 138 / 151 / 171 / 197 / 227 / 281 / 298 / 360 付近）は素通し。
- 制約: 完全な User-Agent を保存していないため、TASK-386 適用日（2026-08-09）より前のデータは遡ってボット分類できない。除外を入れると、それ以前の期間は「ボットが人間として残る」ままになる。この非連続性をダッシュボード上でどう扱うかを決める必要がある。
- 設計判断が要る点: 全集計から一律に除外するのか、人間/全体を切り替えられるようにするのか。前者なら BOT_MATCH を各クエリの WHERE に足す形、後者なら表示側にトグルが要る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ダッシュボードの主要な集計（日次推移・国別・referrer 別・OS 別・ダウンロード）で、ロボットの巡回が人間の訪問と混ざらない
- [x] #2 ボット除外の条件が analytics.ts の 1 箇所（BOT_MATCH 相当）に集約され、集計ごとに条件を書き写す形になっていない
- [x] #3 TASK-386 適用日より前の期間はボット分類できないことが、ダッシュボードの表示または注記から読み取れる
- [x] #4 上記の集計がボットを除外することがユニットテストで担保されている（ボット行と人間行を投入し、集計結果に人間だけが現れる）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. analytics.ts の BOT_MATCH を NULL 安全な形（COALESCE(ua_summary, '') LIKE 'bot:%'）へ直し、人間限定の述語 HUMAN_ONLY を同じ 1 箇所に置く。NULL 安全にしないと、分類適用前の ua_summary IS NULL 行が WHERE で黙って全集計から落ちる（LIKE が NULL を返すため）。
2. トグルは設けず一律除外（表示状態を増やさない）。ボットの数はボット専用セクション（uaSplit）だけで見せる。
3. HUMAN_ONLY を適用する: cumulativeTotals / todayTotals / dailySeries / hourlyDistribution / breakdown / recentEvents / eventsAfter。適用しない: uaSplit・uaBreakdown（両方を数えるのが目的）、maxEventId（生の id を返すカーソル）。
4. SSE 経路の手当て（設計レビュー指摘）: eventsAfter に述語を足すと、ボットだけが来た周期で lastId が進まず集計の再描画も起きない（routes/dashboard.tsx:63 が events.length > 0 を条件にしている）。カーソルは生の id のままにするため、各周期で maxEventId を取り、到来検知と lastId の前進はそちらで行う。ただし eventsAfter が上限件数まで返した周期は取りこぼすため、その場合のみ最後に返った id へ進める。
5. dashboard.tsx の注記を、既存の BOT_CLASSIFICATION_START を使って「全集計がボットを除外していること」「この日より前の巡回は分類できず人間側に残ること」を読み取れる文へ更新する。
6. テスト: (a) ボット行＋人間行を投入し各集計に人間だけが現れること、(b) ua_summary が NULL の行が集計から落ちないこと、(c) 将来クエリを足したときに落ちる構造ガード（analytics.ts の 'FROM events' を含むクエリが HUMAN_ONLY を含むか、明示の除外リストにあるかを検査する）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

ボット除外の条件を analytics.ts の HUMAN_ONLY（NOT COALESCE(ua_summary,'') LIKE 'bot:%'）1 箇所に置き、cumulativeTotals / todayTotals / dailySeries / hourlyDistribution / breakdown / recentEvents / eventsAfter へ適用した。トグルは設けず一律除外（表示状態を増やさない）。ボットの数は既存の uaSplit セクションだけで見せる。

## 設計レビュー（/review-design）で直した 2 点

1. SSE のカーソル（項目 3・5）: eventsAfter は最新イベント表の追記経路であると同時に「集計を再描画するか」のトリガ（routes/dashboard.tsx）を兼ねていた。返った行だけでカーソルを進めると、ボットしか来なかった周期で位置が進まず、ロボットのセクションを含む集計が更新されない。カーソルは maxEventId の生の id で進め、上限（STREAM_LIMIT）まで返った周期だけ最後に読んだ id で止める形にした。
2. NULL 安全性（項目 1）: 素の ua_summary LIKE 'bot:%' は ua_summary が NULL のとき NULL を返し、WHERE に置くとその行が人間でもボットでもなく全集計から黙って消える（列は NULL 許容: migrations/20260728165331_init_events.sql:10）。COALESCE(ua_summary, '') で固定し、テストで担保した。

## 担保（破れたら落ちるもの）

- analytics.test.ts「ボット除外の条件が 1 箇所に集約されている」: 集計クエリ本体を TEST_ANALYTICS_SOURCE バインディング（vitest.config.ts）で読み、FROM events を含むクエリが HUMAN_ONLY を経由するか意図的な除外（BOT_MATCH を直接使う uaSplit / uaBreakdown、生の id を返す maxEventId）に限ることを検査する。実測: hourlyDistribution から述語を外すと落ちることを確認した。
- dashboard.test.ts「ロボットの巡回は event として流さないが、集計は配信し直す」: 上記 1 の修正を戻す（arrived を events.length > 0 に戻す）と落ちることを確認した。

## 検証

- npm run typecheck: エラーなし
- npx vitest run: 8 ファイル 138 件すべて成功
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ダッシュボードの全集計からロボットの巡回を除外した。除外条件は analytics.ts の HUMAN_ONLY 1 箇所に集約し、累計・本日・日次推移・時間帯・国別・参照元別・OS 別・接続元組織別・バージョン別ダウンロード・最新イベント・SSE の追記に適用。人間とロボットの内訳セクション（uaSplit）と SSE のカーソル（maxEventId）だけは意図的に生のまま残した。設計レビューで見つかった 2 点（ボットのみ到来した周期で集計が再描画されない／ua_summary が NULL の行が全集計から消える）を実装前に潰し、それぞれ戻すと落ちるテストを付けた。TASK-386 適用日より前は遡って分類できないことをダッシュボードの注記に明記。検証: npm run typecheck エラーなし、npx vitest run 138 件成功。
<!-- SECTION:FINAL_SUMMARY:END -->
