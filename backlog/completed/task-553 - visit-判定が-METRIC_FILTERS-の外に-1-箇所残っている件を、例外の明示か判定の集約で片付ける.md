---
id: TASK-553
title: visit 判定が METRIC_FILTERS の外に 1 箇所残っている件を、例外の明示か判定の集約で片付ける
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-25 02:01'
updated_date: '2026-08-25 02:25'
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
- [x] #1 eventBreakdowns の visit 判定が、認められた例外として機械的に担保されているか、METRIC_FILTERS から導かれているかのどちらかになっている
- [x] #2 指標の述語を METRIC_FILTERS から導かない箇所が新たに増えたら落ちる（HUMAN_ONLY の構造ガードと同等の担保がある）
- [x] #3 上の「着手前に決めること」2 点の結論が Implementation Notes に残っている
- [x] #4 site の vitest が通り、流入面のページ別・言語別と配信面のホスト別の値が変わっていないことをテストが固定している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. (b) 判定を寄せる: metricExpression の TS 版 matchesMetric を analytics.ts に足し、eventBreakdowns の kind === 'visit' を matchesMetric(row, METRIC_FILTERS.visit) に置き換える
2. SQL と TS の等価性テスト: METRIC_EXPR と metricOf を export し、kind × source × page の組み合わせ行で SQL の判定と TS の判定が一致することを固定する
3. 構造ガード: analytics.ts のコメントを除いたソースに対し、TS 側の kind リテラル比較が 0 件、SQL の kind 述語が metricExpression + UNIQUE_SOURCE_FILTERS の 4 箇所だけであることを固定する（UNIQUE_SOURCE_FILTERS は母集団の述語で指標ではないため明示的な例外）
4. page ?? '/' の丸めは指標の述語ではなく軸ラベルの丸めとして残す判断を doc に書く
5. site の vitest を通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 着手前に決めたこと

**(a) か (b) か → (b) を主、(a) を残りへ。** `eventBreakdowns` の `row.kind === 'visit'` は `metricOf`（`METRIC_EXPR` の TS 版）へ寄せた。SQL の述語（`metricExpression`）と TS の述語（`matchesMetric`）は kind / source / page の三条件が 1 対 1 に対応し、両者が同じ行に同じ指標を返すことを全 kind × source × page（5×4×3=60 行）の総当たりテストで固定したので、「異なる表現の間で同じ `METRIC_FILTERS` から導く」形は作れた。その上で、判定を寄せられない箇所（`UNIQUE_SOURCE_FILTERS`）は HUMAN_ONLY と同じ形の件数ガードで明示的な例外にした。母集団（異なり数）の述語であって指標（延べ件数）ではなく、`METRIC_FILTERS.visit` に page 条件が戻っても母集団はサイト全体のままであるべきなので、導出させない。

**`page ?? '/'` の丸めは TASK-551 のあとも要る。** ただしこれは指標の述語ではなく**軸ラベルの丸め**で、`METRIC_FILTERS` からは導かない（`METRIC_FILTERS.visit` は TASK-551 で page 条件を失ったので、そもそも導く元が無い）。ページ別の表では列の導入前の行をどこかの行に置く必要があり、'/' の行が「LP への訪問」と「列導入前の訪問」の和になる点は analytics.ts の doc と site/README.md に書いた（表示上は分けない——分けると「列導入前」という運用の都合が画面に出る）。

## 実測

- `npm test`（site）: 13 files / 429 tests 通過。`npm run lint`（--type-aware）・`format:check` もゼロ件
- 追加した 2 つのガードが修正を戻すと落ちることを確認: `metricOf(row) === 'visit'` を `row.kind === 'visit'` へ戻す → 「指標の述語を METRIC_FILTERS の外に書く箇所が無い」が失敗。`matchesMetric` の source の COALESCE 既定を 'lp' → 'sparkle' に変える → 「SQL 側の判定と TS 側の判定が同じ行に同じ指標を返す」が失敗
- 評価順の入れ替え（`metricKeys().toReversed()`）では落ちない。現在の述語が互いに素なため。順序が意味を持つ述語を足した時点で総当たりテストが差を出す
- site/README.md の「「ページアクセス」指標は `page = '/'` のまま」は TASK-551 で実態と食い違っていたので、同時に現在の仕様へ直した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
eventBreakdowns の visit 判定を METRIC_FILTERS から導く形（metricOf / matchesMetric）へ寄せ、寄せられない UNIQUE_SOURCE_FILTERS を件数ガードで明示的な例外にした。SQL と TS の判定一致を全 kind × source × page の総当たりで固定し、両ガードが修正を戻すと落ちることを実測で確認した。site の vitest 429 件通過。
<!-- SECTION:FINAL_SUMMARY:END -->
