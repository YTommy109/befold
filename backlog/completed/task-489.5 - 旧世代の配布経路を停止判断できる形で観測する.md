---
id: TASK-489.5
title: 旧世代の配布経路を停止判断できる形で観測する
status: Done
assignee: []
created_date: '2026-09-03 15:23'
updated_date: '2026-09-03 15:37'
labels: []
dependencies: []
parent_task_id: TASK-489
ordinal: 800000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-489.1 と TASK-489.4 が「観測手段は TASK-489.2 が用意する」と参照しているが、その番号のタスクは起票されていなかった。ここで埋める。

## 何が足りていないか（本番 D1 実測 2026-09-04）

`/dashboard/delivery` は「配布ホストと旧経路（全期間の累計）」しか出しておらず、**累計と「最後に発生」だけでは停止判断ができない**。実測で 3 つの形で破れている。

1. **一過性のスパイクと定常流入が同じ見え方になる。** GitHub フォールバック `archive-dmg` は累計 266 件・最終発生 2026-09-02 で「まだ落ち続けている」ように見えるが、日次に割ると 8/19-8/26 に 262 件が集中し（OVH の bot:other 126 / GPTBot 42 / SEMrush 42 / Amazonbot 42）、8/27 以降は 9/02 の 4 件だけ。クローラが旧タグを一斉に舐めた跡である。
2. **旧ホストに「最後に発生」列が無い。** `lastSeenAt` を持つのは `FallbackSplit` だけで、ホスト別の `Split` は持たない。停止条件が ADR 0007 で定義されているのは旧ホスト側（同 :117-118）なので、非対称が逆を向いている。実測では workers.dev は累計 26 件・最終 2026-09-03 14:26。
3. **「最後に発生」をボットが作っている。** 停止条件は人間の有無で決めるはずだが、workers.dev の直近の発生は Googlebot / Meta-ExternalAgent / facebookexternalhit で、Sparkle は 2026-08-18（So-net）と 08-21（IIJ）の 2 件が最後。フォールバック側の「人間」14 件も全て Safari + as_org が `6 COLLYER QUAY` / `16 COLLYER QUAY` / `ACEVILLE PTE.LTD.`（DATACENTER_ORG_PATTERNS に無いシンガポールの住所名義）。人間とボットの最終発生を分けないと条件判定に使えない。

## このタスクでやること

1. 経路ごとの日次推移（直近 30 日）を出す
2. 列を「累計 / 直近 30 日 / 直近 7 日 / 最終発生」に揃え、旧ホスト（`Split`）にも最終発生を持たせて `FallbackSplit` との非対称を解消する
3. 最終発生を人間とボットで分けて出す

## やらないこと

- **停止条件の判定そのものの表示**（「人間 0 件が N 日継続 → あと X 日で条件成立」）は TASK-489.1 の ADR が N を決めてから。ここでは素材を出すところまで。
- **as_org の分類の変更**（COLLYER QUAY 系をデータセンターに含めるか）は ADR 0008 の範囲で、このタスクでは触らない。人間とボットを分けて出せば、分類を変えなくても読み取れる。

## 制約

`site/test/query-count.test.ts` がクエリ本数の上限を持つ。軸ごとにクエリを増やす形にすると落ちる（`eventBreakdowns` が 1 本のクエリを TS 側で畳んでいるのはこのため）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 配布ホスト別・GitHub フォールバック経路別のそれぞれに、直近 30 日の日次推移が出ている
- [x] #2 両方の表が「累計 / 直近 30 日 / 直近 7 日 / 最終発生」の列を持ち、旧ホストにも最終発生が出ている
- [x] #3 最終発生が人間とボットで分かれて出ており、ボットだけが来ている経路をそう読める
- [x] #4 delivery 面のクエリ本数が query-count.test.ts の上限内に収まっている
- [x] #5 累計だけでは停止判断ができない理由が画面の注記に書かれている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
`/review-design` を 1 回実施した結果を反映したもの（2026-09-04）。

## 型

- delivery 専用に `RouteSplit` を新設し、ホスト別・フォールバック別の両方をこの型にする。
  持つのは 累計(人間/ロボット) / 直近 30 日(人間) / 直近 7 日(人間) / 人間の最終発生 / ロボットの最終発生。
- **`Split` には足さない。** `Split` は `visits.byPage` / `byDisplayLang` / `byBrowserLang` と共有で
  （analytics.ts:750-754）、そちらに停止判断の列が漏れる。既存 doc コメント（同 :770-772）の
  「意味の違う 2 つの表を同じ型にしない」は正しく、統一すべきなのは Split 全体ではなく
  「停止判断の対象になる経路」2 表。差分（0 件の既知ホストも行に残すか）は型ではなく畳む関数に置く。
- `FallbackSplit` は `RouteSplit` へ畳んで廃止する。

## クエリ

- 累計・窓別・最終発生は既存の `eventBreakdowns` の SELECT 句を拡張して取る（**本数を増やさない**）。
  GROUP BY に `is_non_human` が既に居るので、人間/ボットの最終発生は畳む側で 2 つの max を持てば足りる。
- 日次推移は新規クエリ 1 本（delivery 1 → 2 本、全体 17 → 18。上限はページ 8 / 全体 20 のまま据え置く）。
  日 × is_non_human で GROUP BY し、`SUM(host = LEGACY_HOST)` と `SUM(kind = 'github_fallback')` を並べる
  （1 件が両方に当たりうるので行を分けず列で数える）。ゼロ埋めは `jstDaysInWindow`。
- **新クエリは `HUMAN_ONLY` 検査（test/analytics.test.ts:545-562）の除外側に倒す。**
  ボットも数えるのが目的なので、`eventBreakdowns` と同じく `NON_HUMAN_MATCH` を式に含める形にする。

## 窓

- `DELIVERY_WINDOW_DAYS = 30` を新設する。`DAILY_WINDOW_DAYS = 14` を流用すると、実測の
  フォールバック 266 件のうち 8/19-8/21 の 172 件が窓外へ落ち、「スパイクだった」という肝心の事実が消える。
- `summarizeDelivery(db)` を `(db, now)` にする（routes/dashboard.tsx:139。users と同じ形）。

## 表示

- 表の列は `経路 | 人間 累計 | 人間 30日 | 人間 7日 | 人間 最終 | ロボット 累計 | ロボット 最終`。
  停止判断は人間で決まるので、ロボットの 30 日 / 7 日は表から落として日次グラフで読む（9 列は広すぎる）。
- グラフは既存の `SeriesChart`（凡例 + グループ化バー、色は 5 スロット固定）を流用し 2 枚。
  「旧ホストへのアクセス」「GitHub フォールバック」、各 2 系列（人間 / ロボット）。
  正規ホストは停止判断の対象外なので描かない。
- **「未記録」ホスト行の最終発生は `null`（—）にする。** host 列は導入後の全行に入るため、
  この行の最終発生（実測 2026-08-16 13:27 JST）は列の導入時期そのものを指し、「まだ来ている」と誤読される。
  理由を注記に書く。

## 破れたら落ちるもの

- 30 日窓の外のイベントが「直近 30 日」に入らない
- 同じ経路で人間 / ロボットの最終発生が別々に出る（両方を 1 テストで検証）
- 0 件の既知ホストが行として残り、最終発生が null になる
- `visits.*` が `Split` のままであること（型で担保。テスト不要）
- query-count が上限を上げずに通る
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装は 3 点とも入れた（1 日次推移 / 2 列の統一と旧ホストの最終発生 / 3 人間とボットの最終発生の分離）。

## 実際に入れた形

- `FallbackSplit` を廃し、旧ホスト別とフォールバック別を `RouteTotals`（全期間の累計 + 人間/ボットの最終発生）と
  `RouteSplit`（= `RouteTotals` + 窓の件数）へ統一した。**窓の件数を `RouteTotals` に持たせなかったのは**、
  累計は `eventBreakdowns`、窓は `deliveryWindow` と取得元が別のクエリで、1 つの型にすると `eventBreakdowns` が
  窓の列を 0 のまま返し「まだ埋めていない 0」と「本当に 0 件」が型の上で区別できなくなるため。
- 累計・最終発生は既存の `eventBreakdowns` の畳み込みだけを変えて取った（**クエリを増やしていない**）。
  GROUP BY に `is_non_human` が既に入っていたので、人間/ボットの最終発生は畳む側で 2 つの max を持てば足りた。
- 窓（30 日 / 7 日）と日次推移は `deliveryWindow` の新規クエリ 1 本。delivery 面 1 → 2 本、全体 17 → 18。
  **上限は据え置き**（ページ 8 / 全体 20）。
- 窓の長さは `DeliverySummary` に載せず、表示側が `DELIVERY_WINDOW_DAYS` / `DELIVERY_RECENT_DAYS` を直接読む。
  面ごとの集計を 1 つへ畳むテスト（`summarizeAll`）で `windowDays` が利用者面の 14 と衝突し、片方が黙って
  上書きされるため。
- delivery だけが使っていた `SplitTable` は `RouteTable` に置き換わったので削除した。

## 破れたら落ちることを確認した（実測）

修正を戻して落ちることまで確かめた。

- 窓を 10000 日に広げる → 「窓の外の発生は『直近』に入らないが累計には残る」1 件が落ちる
- 最終発生を人間/ボットで混ぜる → 内訳の 5 件が落ちる（「最後に発生した時刻を人間とロボットで分ける」を含む）
- `formatLastSeen` を `formatJst(at ?? 0)` に戻す → 「一度も発生していない経路の最終発生は 0 ではなく『—』で出す」が落ちる

site のテストは 418 件すべて通過。tsc / oxlint --type-aware / oxfmt / markdownlint も通した。

## 次（TASK-489.1 へ）

停止条件の判定そのものの表示（「人間 0 件が N 日継続 → あと X 日で条件成立」）は入れていない。
N を決めるのは TASK-489.1 の ADR。**素材は揃った**ので、ADR が N を決めれば表示は足せる。
<!-- SECTION:NOTES:END -->
