---
id: TASK-493
title: アップデートの取り込み状況（確認→更新の転換率とリリース後の取り込み曲線）を測れるようにする
status: To Do
assignee:
  - '@Tommy109'
created_date: '2026-08-16 02:39'
updated_date: '2026-08-16 08:25'
labels: []
milestone: m-7
dependencies:
  - TASK-500
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 指標の定義

### 1. 更新転換率（同日ユニーク基準・チャネル別）

- 分母: その日に update_check を送ったユニーク visitor_token 数（TASK-494 の
  UNIQUE_SOURCE_FILTERS.update_check_<ch> と同じ母集団）
- 分子: 同じ日・同じチャネルで update_check と download(source='sparkle') の
  **両方**を持つユニーク visitor_token 数（積集合）
- 併記: 「確認の記録がない更新」（dl かつ not chk）のユニーク数

分子を積集合にする理由（実測）: 本番 D1 に dl_only が実在する（2026-08-14 stable
1 件 / 2026-08-13 stable 1 件）。単純な dl/chk は 100% を超えうる。visitor_token は
生 UA をハッシュ材料に含むため（visitor.ts:24-28）、appcast 取得と DMG 取得で
UA が変われば別トークンになる。この取りこぼしを率の中に隠さず別系列で出す。

指標名は「確認から更新まで進んだアクセス元の割合」とし、分母の実数を併記する
（AC #2）。「利用者の割合」とは言わない。

### 2. リリース後の取り込み曲線（タグ別・チャネル別）

- 0 日目の起点: そのタグの sparkle download の**初出時刻**（events 内 MIN）
- 経過日ごとの累積ユニーク visitor_token 数
- 率は出さず実数のみ（AC #8 の母数の小ささ: 実測でタグ単位ほぼ n=1、最大 3）

## クエリ本数（AC #7: MAX_QUERIES=13 を超えない）

現状 13 本で満杯。新指標は token 単位／tag 単位に畳む必要があり、既存の
日別推移クエリ（行単位の CASE）には相乗りできない。

**先に単純化して枠を空ける**: breakdown() が version / country / referrer で
3 本発行しているのを、metricBreakdowns と同じ形（軸を UNION ALL で行に落とし
ROW_NUMBER() OVER (PARTITION BY axis) で上位 N を切る）で 1 本に畳む。
13 → 11 本。ここへ新指標 1 本（updateFlow）を入れて 12 本。

updateFlow は UNION ALL の 2 枝を 1 本で引く:
- 枝 conversion: day / channel / chk_uniq / both_uniq / dl_only_uniq
- 枝 adoption: tag / channel / 経過日 / 累積ユニーク

## 実装順

1. breakdown() 3 本を 1 本へ畳む（単純化。指標を足す前に枠を空ける）
2. updateFlow クエリと型を追加（HUMAN_ONLY を必ず通す）
3. ダッシュボードに「アップデートの取り込み」セクションを追加。
   転換率は分母の実数併記、取り込み曲線は実数のみ、チャネル別に分ける
4. テスト: analytics（積集合の分子・dl_only・チャネル分離・窓の境界・ボット除外）、
   dashboard（表示文言）、query-count（内訳コメント更新、本数 12）
5. リリース公開日の求め方とその限界を Implementation Notes に記録（AC #4）
6. 新しい記録列を追加せずに済んだことを Implementation Notes に記録（AC #6）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 着手条件（TASK-500 待ち）

**TASK-500（ダッシュボードの複数ページ分割）が完了すれば着手できる。**

理由: 本タスクは 13 個目のセクションを追加する変更だが、ダッシュボードは既に
1 ページ 12 セクション・13 クエリで `MAX_QUERIES = 13`（site/test/query-count.test.ts:44）が
満杯。先に指標を足すと、13 セクションの状態から分割することになり、割り振りと
テスト修正が一度余計に増える。ユーザー判断により分割を先行させる（2026-08-16）。

TASK-500 完了後、本タスクの新セクションは分割後の該当ページへ載せる。
下の Implementation Plan のうち「breakdown() 3 本を 1 本へ畳んで枠を空ける」手順は、
TASK-500 でクエリ本数の上限がページ単位になれば不要になる可能性がある。着手時に再判断する。
<!-- SECTION:NOTES:END -->
