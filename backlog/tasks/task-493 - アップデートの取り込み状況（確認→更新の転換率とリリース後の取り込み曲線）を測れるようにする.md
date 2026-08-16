---
id: TASK-493
title: アップデートの取り込み状況（確認→更新の転換率とリリース後の取り込み曲線）を測れるようにする
status: To Do
assignee: []
created_date: '2026-08-16 02:39'
labels: []
milestone: m-7
dependencies:
  - TASK-491.2
priority: medium
ordinal: 731000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「新版を出したあと、どれだけの利用者が実際に上がっているか」をダッシュボードで読めるようにする。TASK-491 が「今どのバージョンが動いているか（在庫）」を測るのに対し、こちらは「更新が進んでいるか（流れ）」を測る。

## 現状（実測）

必要なデータは**すでに揃っており、新しい記録は要らない可能性が高い**。本番 D1（`befold-analytics`、2026-08-16 時点、全 538 行）の実測:

- `kind='update_check'` が 132 件（Sparkle 101 / curl 31、develop 91 / stable 41）
- `kind='download'` かつ `source='sparkle'` が 16 件。`version` に更新先タグが入っている（`v1.12.3`, `v1.12.4-dev.5` など）
- 両者は `site/src/analytics.ts:44-49` の `METRIC_FILTERS` で `update_check` / `update_download` として既に別指標になっており、ダッシュボードにも並んでいる（`site/src/analytics.ts:118-124`）

つまり「並んではいるが、関係として読めない」のが現状。数として隣り合っているだけで、転換率も時間軸での取り込み具合も出ていない。

## 出したい指標

1. **確認 → 更新の転換率。** 期間内の `update_download` ÷ `update_check`。「更新は見えているのに当てていない利用者」の規模が読める。
2. **リリース公開からの経過日数別の取り込み曲線。** あるタグについて、公開日から N 日後までに `source='sparkle'` の download が何件積み上がったか。「新版を出して何日で何割が上がるか」が分かる。

## 決めること

- **転換率の分母が何を意味するか。** `update_check` はアプリが定期的に飛ばすため、延べ件数は利用者数ではなく起動回数に比例する。単純な比は「1 回の確認あたりの更新率」であって「更新した人の割合」ではない。日別のユニーク `visitor_token` を分母にするなど、何を 1 と数えるかを決めて指標名に反映する（`visitor_token` は `sha256(ip \0 ua \0 JST 日付)` で日ごとに変わる。`site/src/lib/visitor.ts:26-30`）。
- **リリース公開日をどこから取るか。** events にはリリース公開時刻が無い。そのタグの `source='sparkle'` download の初出時刻で代用するか、R2 の `latest.json` / GitHub Releases の公開日を引くかを決める。前者は Worker を通らなかった配布を取りこぼす。
- **チャネルを分けるか。** 実測では develop が多数（`update_check` 132 件中 91 件）で、これは開発機からの確認。混ぜると stable の取り込み具合が読めない。
- **母数が小さい期間の見せ方。** 現時点の総イベント数は 538 件で、タグ単位に割ると 1 桁になる。率だけを大きく出すと誤読を招くため、分母を併記するなどの扱いを決める。

## 注意

- ボット除外は既存の `HUMAN_ONLY` を使い、新しい判定を作らない。除外条件が 1 箇所に集約されていることは規約テスト `site/test/analytics.test.ts:299` が担保している。
- `summarize()` の発行クエリ数には上限テストがある（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。指標を足す際にクエリを線形に増やさない。既存の `metricBreakdown`（`site/src/analytics.ts`）が「指標を行に持たせて 1 本にまとめる」形をとっているので、同じ手を使う。
- 日付・時間帯のバケットは JST（`site/src/lib/jst.ts` が唯一の定義元）。
- 指標を新設する変更のため、実装着手前に `/review-design` を 1 回回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 アップデート確認に対する実際の更新ダウンロードの転換率がダッシュボードで読める
- [ ] #2 転換率の分母が何を数えたものかが画面上で分かり、分母の実数も併記されている
- [ ] #3 リリース公開からの経過日数別に、更新の取り込みがどこまで進んだかが読める
- [ ] #4 リリース公開日を何から求めたか、その限界（Worker を通らない配布を取りこぼすか等）が Implementation Notes に記録されている
- [ ] #5 stable と develop のチャネルが混ざらずに読める
- [ ] #6 新しい記録列を追加せずに済んだかどうかが Implementation Notes に記録されている
- [ ] #7 summarize() の発行クエリ数が既存の上限テストを超えない
- [ ] #8 site の vitest と typecheck が通る
<!-- AC:END -->
