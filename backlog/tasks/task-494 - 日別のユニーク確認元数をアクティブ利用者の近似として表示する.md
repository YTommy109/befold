---
id: TASK-494
title: 日別のユニーク確認元数をアクティブ利用者の近似として表示する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 02:40'
updated_date: '2026-08-16 06:28'
labels: []
milestone: m-7
dependencies: []
priority: medium
ordinal: 726500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「今どれくらいの人が befold を使っているか」の近似をダッシュボードで読めるようにする。

## 現状（実測）

- `events` には `visitor_token` があり、`sha256(ip \0 ua \0 JST 日付)` で計算される（`site/src/lib/visitor.ts:26-30`）。**日ごとに値が変わる設計**なので、通算のユニーク利用者数には使えないが、**1 日の中でのユニーク数は数えられる**。
- 現在この列を使った集計は無い。ダッシュボードの日別推移（`site/src/analytics.ts:200` 付近）はイベント件数の合計であって、ユニーク数ではない。
- アプリは起動時にアップデート確認を飛ばすため（`kind='update_check'`、本番 D1 で 132 件／2026-08-16 時点）、その日にアプリを起動した端末の近似として使える。サイト訪問（`visit`）とは母集団が違うので、混ぜずに別系列として出す。

## 決めること

- **どのイベント種別を母集団にするか。** `update_check` はアプリ利用者、`visit` はサイト訪問者で、意味が違う。両方出すなら別系列にする。
- **近似であることをどう伝えるか。** これは「その日にアップデート確認を飛ばした端末のユニーク数」であって、アクティブ利用者数そのものではない。IP が変われば別カウントになり（モバイル回線・VPN で膨らむ）、同一 IP・同一 UA の複数端末は 1 になる（NAT 配下で縮む）。この限界が画面から読み取れる必要がある。指標名を「アクティブ利用者数」と言い切らない。
- **チャネルを分けるか。** 実測では `update_check` 132 件中 91 件が develop で、開発機からの確認が多い。stable と分けないと利用者規模を過大に見積もる。
- **通算ユニークを出すか出さないか。** `visitor_token` の日次ソルトは意図的な設計（追跡しない）なので、通算ユニークを出すには設計変更が要る。**このタスクでは行わず**、必要と判断したらプライバシー方針として ADR を起こす。判断を Implementation Notes に残す。

## 注意

- ボット除外は既存の `HUMAN_ONLY` を使う（除外条件の一元化は規約テスト `site/test/analytics.test.ts:299` が担保）。ただし curl からの `update_check` が実測で 31 件あり、これはボット判定に当たらず人間側に計上される。近似の精度に効くため、TASK-490（ボット判別の精度見直し）の結論と整合させる。
- 日バケットは JST（`site/src/lib/jst.ts` が唯一の定義元）。`COUNT(DISTINCT visitor_token)` は既存の `JST_DAY_EXPR` によるグループ化と組み合わせる。
- `summarize()` の発行クエリ数上限テストに注意（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。既存の日別推移クエリに相乗りできないかを先に検討する。
- 指標を新設する変更のため、実装着手前に `/review-design` を 1 回回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 日別のユニーク確認元数がダッシュボードで読める
- [x] #2 これが利用者数そのものではなく近似であること、および過大・過小に振れる条件が画面上で分かる
- [x] #3 サイト訪問とアプリ利用が別系列として読める
- [x] #4 stable と develop のチャネルが混ざらずに読める
- [x] #5 通算ユニークを出さない判断とその理由が Implementation Notes に記録されている
- [x] #6 summarize() の発行クエリ数が既存の上限テストを超えない
- [x] #7 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 既存の dailySeries クエリに相乗りする形で、ユニーク数を母集団別に分ける。
   COUNT(DISTINCT CASE WHEN <述語> THEN visitor_token END) を SELECT 句へ足すだけなので
   クエリ本数は増えない（query-count.test.ts の MAX_QUERIES=13 に影響しない）。
2. 母集団の定義元を 1 箇所に置く（UNIQUE_SOURCE_FILTERS）。
   - visit: kind='visit'（ページで絞らない。サイト全体の訪問者）
   - update_check_stable / update_check_develop / update_check_unrecorded:
     kind='update_check' AND channel = ... / IS NULL
   channel NULL を落とさず 未記録 系列として残す（foldHosts と同じ理由）。
3. DailyPoint.uniqueVisitors（全 kind 混在）を uniqueSources: Record<UniqueSourceKey, number>
   へ置き換える。混在系列は母集団が違うものの合成で、この指標の趣旨に反するため
   足すのではなく差し替える（単純化）。today.uniqueVisitors / cumulative.visitorDays は据え置き。
4. ダッシュボードに専用セクション「日別のユニーク確認元」を追加し、
   4 系列のグラフ + 近似の限界を述べる note を置く（IP 変動で過大、NAT で過小、
   日次ソルトのため通算不可、curl 等の自動アクセス混入、UA 分類の遡及不可）。
   日毎の推移グラフからは混在ユニーク系列を外す。
5. テスト: analytics.test.ts に母集団分離・チャネル分離・ページ非依存のケース、
   dashboard.test.ts に系列数と note の表示を追加。
6. 通算ユニークは出さない判断とその理由を Implementation Notes に記録する。
7. site の vitest / typecheck を通す。

--- /review-design の結果（実装前）---
8. チャネル列挙の定義元を lib/github.ts の CHANNELS 1 本に集約し、
   APPCAST_UPSTREAM を Record<Channel,string> にする。schema.ts の z.enum と
   ユニーク系列の生成をそこから導く（チャネル追加時に系列が増えないことを型で防ぐ）。
9. 「ユニーク」の語が画面上で 2 つの意味で並ばないよう、当日カード
   （'ユニーク訪問者'）と累計カード（'延べ訪問者'）のラベルも
   「アクセス元」の語彙へそろえる（ラベルのみ。状態も経路も増やさない）。
10. query-count.test.ts の内訳コメントに TASK-494 の行を足す（本数は 13 のまま）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 通算ユニークを出さない判断（AC #5）

**出さない。** `visitor_token` は `sha256(ip \0 ua \0 JST 日付)` で、日付をハッシュの
材料に混ぜてある（site/src/lib/visitor.ts:17-28）。これは「日をまたぐ同一人物を
追えないようにする」ための意図的な設計であって、集計の都合で回避してよい制約では
ない。通算ユニークを出すには永続的な識別子（Cookie・端末 ID・ソルト固定のハッシュ）が
必要で、それは「追跡しない」という現在の方針そのものの変更にあたる。

このタスクの範囲では行わない。必要と判断した時点で、プライバシー方針として ADR を
起こしてから設計変更する。日次ユニークの近似で足りるか（アプリの利用規模を月次で
見たいだけなら、日次ユニークの推移で判断できる）を先に問うこと。

## 実装の要点

- 母集団の述語は `UNIQUE_SOURCE_FILTERS`（site/src/analytics.ts）1 箇所。
  チャネル別系列は `lib/github.ts` の `CHANNELS` から生成する。
- チャネルの列挙が github.ts と schema.ts に二重にあったのを解消し、
  `CHANNELS` を唯一の定義元にした（`APPCAST_UPSTREAM` は `Record<Channel, string>`、
  `channelSchema = z.enum(CHANNELS)`、表示名は `Record<Channel, string>`）。
  チャネルを増やすと appcast・記録・集計系列が同時に増え、表示名を書くまで型で落ちる。
- 日毎の推移から混在ユニーク系列（全 kind 合算）を外した。母集団の違うものの合算で、
  どの規模も表さない数だったため（足すのではなく差し替え）。
- 「ユニーク」の語が 2 つの意味で並ばないよう、当日カード・累計カードのラベルを
  「アクセス元」の語彙へそろえた（ラベルのみ。状態も経路も増やしていない）。
- channel が NULL の update_check は「チャネル未記録」系列として残す
  （0 でも系列を消さない。`foldHosts` と同じ理由）。本番にこの行が存在するかは未確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
日別のユニークアクセス元を母集団別（サイト訪問 / アプリ stable / develop / チャネル未記録）に出す専用セクションをダッシュボードへ追加した。述語は UNIQUE_SOURCE_FILTERS 1 箇所、チャネル別系列は lib/github.ts の CHANNELS から生成する（チャネルの列挙が github.ts と schema.ts に二重にあったのを CHANNELS へ集約し、表示名を Record<Channel,string> にして系列だけ増えない形にした）。既存の日別推移クエリの SELECT 句に COUNT(DISTINCT CASE WHEN ...) を並べたのでクエリ本数は 13 のまま。母集団の違うものを合算した混在ユニーク系列は日毎の推移から外し、当日・累計カードのラベルも「アクセス元」の語彙へそろえた。近似の限界（IP 変動で過大 / NAT で過小 / 通算は出せない / curl は残る）は当該セクションの注記に出す。通算ユニークは出さない判断とその理由を Implementation Notes に記録。検証: site の vitest 256 件全通過（12 ファイル）、tsc --noEmit クリーン、markdownlint-cli2 0 件。チャネル判定を壊す変異を入れると新規テスト 2 件が落ちることを実測して、テストが空振りしていないことを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
