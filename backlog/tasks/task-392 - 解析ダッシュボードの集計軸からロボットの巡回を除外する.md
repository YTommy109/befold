---
id: TASK-392
title: 解析ダッシュボードの集計軸からロボットの巡回を除外する
status: To Do
assignee: []
created_date: '2026-08-09 13:33'
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
- [ ] #1 ダッシュボードの主要な集計（日次推移・国別・referrer 別・OS 別・ダウンロード）で、ロボットの巡回が人間の訪問と混ざらない
- [ ] #2 ボット除外の条件が analytics.ts の 1 箇所（BOT_MATCH 相当）に集約され、集計ごとに条件を書き写す形になっていない
- [ ] #3 TASK-386 適用日より前の期間はボット分類できないことが、ダッシュボードの表示または注記から読み取れる
- [ ] #4 上記の集計がボットを除外することがユニットテストで担保されている（ボット行と人間行を投入し、集計結果に人間だけが現れる）
<!-- AC:END -->
