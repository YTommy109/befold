---
id: TASK-553
title: visit 判定が METRIC_FILTERS の外に 1 箇所残っている件を、例外の明示か判定の集約で片付ける
status: To Do
assignee: []
created_date: '2026-08-25 02:01'
labels: []
dependencies:
  - TASK-551
priority: low
type: chore
ordinal: 801000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「その行は visit か」「その行はどのページか」を決める判定が、`METRIC_FILTERS` とは独立にもう 1 箇所ある。

## 現状（2026-08-25 にコード確認・TASK-551 の設計レビューで発見）

指標の述語は `site/src/analytics.ts` の `METRIC_FILTERS` と `metricExpression` が唯一の定義元、という規約がある。`KIND_COUNT_COLUMNS`・`METRIC_EXPR`・各所の `metricExpression(METRIC_FILTERS.x)` はすべてそこから導かれ、`analytics.test.ts` の「「ページアクセス」の全系列が…」がその共有を検査している。

ところが流入面の「ページ別の訪問」「言語別の訪問」と配信面のホスト別を作る `eventBreakdowns` は、この経路を通らない。

- SQL は kind を絞らず `GROUP BY kind, page, display_lang, browser_lang, host, fallback, is_non_human` で引く
- visit かどうかの判定は **TS 側**（`kind === 'visit'` で絞る `visitRows`）
- page の丸めも **TS 側**（`foldSplits(visitRows, (row) => row.page ?? '/')`）

`COALESCE(page,'/')` を SQL へ置かないのは意図的で、コメントに理由が書かれている。page が NULL の行には「page 列導入前の visit（当時は LP のみ）」と「ページの概念が無い download / update_check」の 2 種類があり、後者に `'/'` を与えると嘘になるため。丸めを visit 行だけに限る必要があり、それを 1 本のクエリでやるには TS 側へ出すのが素直、という判断。

**判断そのものは妥当で、今回の TASK-551 でも壊れない。** 問題は、その結果として「visit を判定する場所」と「page NULL を LP に丸める場所」が `METRIC_FILTERS` の外に 1 つ残っており、**規約の側にはそれを認める記述も、破れたら落ちるものも無い**こと。

`analytics.test.ts` の「自動アクセス除外の条件が 1 箇所に集約されている」は `HUMAN_ONLY` について同種の構造ガードを持ち、意図的な例外を `exempt` 配列（`TRAFFIC_CLASS_EXPR` / `TRAFFIC_LABEL_EXPR` / `NON_HUMAN_MATCH` / `MAX(id)`）として**明示**している。指標の述語側には対応するものが無い。

## やること

`eventBreakdowns` の TS 側判定を、規約の中で扱える形にする。方針は着手前に決めること。

## 着手前に決めること

- **どちらへ倒すか。**
  - (a) 例外として明示する: `HUMAN_ONLY` の `exempt` と同じく、「指標の述語を `METRIC_FILTERS` から導かない箇所」を列挙する構造ガードを足し、`eventBreakdowns` をそこに載せる。判定は動かさず、認めた例外であることを機械で担保する。
  - (b) 判定を寄せる: `kind === 'visit'` の絞り込みと `page ?? '/'` の丸めを `METRIC_FILTERS` から導ける形に書き換える。SQL へ戻すのではなく、TS 側で `METRIC_FILTERS.visit` を読んで判定するヘルパを 1 つ作るなど。
  - (a) は安いが判定は 2 箇所のまま。(b) は 1 箇所に寄るが、SQL の述語と TS の述語という異なる表現の間で「同じ `METRIC_FILTERS` から導く」形を作れるかを確かめる必要がある。
- **`page ?? '/'` の丸めが TASK-551 のあとも要るか。** TASK-551 で `METRIC_FILTERS.visit` から page 条件が消える。流入面の「ページ別の訪問」で page NULL 行を `/` に寄せる丸めは、指標側とは独立に必要かどうかを確認すること（`/` の行が「LP への訪問」と「列導入前の訪問」の和になっている点を、表示上どう扱うかを含む）。

## 背景

TASK-551 の設計レビュー（チェックリスト項目 1「判定の真実の源」）で、`METRIC_FILTERS.visit` の消費経路を全列挙した際に発見した。TASK-551 の変更では壊れないため、そちらのスコープからは外した。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 eventBreakdowns の visit 判定が、認められた例外として機械的に担保されているか、METRIC_FILTERS から導かれているかのどちらかになっている
- [ ] #2 指標の述語を METRIC_FILTERS から導かない箇所が新たに増えたら落ちる（HUMAN_ONLY の構造ガードと同等の担保がある）
- [ ] #3 上の「着手前に決めること」2 点の結論が Implementation Notes に残っている
- [ ] #4 site の vitest が通り、流入面のページ別・言語別と配信面のホスト別の値が変わっていないことをテストが固定している
<!-- AC:END -->
