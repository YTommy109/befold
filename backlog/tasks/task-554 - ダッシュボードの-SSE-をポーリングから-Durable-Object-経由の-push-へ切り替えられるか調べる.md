---
id: TASK-554
title: ダッシュボードの SSE をポーリングから Durable Object 経由の push へ切り替えられるか調べる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-25 02:17'
updated_date: '2026-08-25 02:34'
labels: []
dependencies: []
type: chore
ordinal: 802000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`site/src/routes/dashboard.tsx` の `/stream` は `POLL_INTERVAL_MS = 2500` で D1 を引き直している。新着が無い周期でも `maxEventId` と `eventsAfter` の 2 本を必ず発行するため、**ダッシュボードのタブを 1 つ開いたままにするだけで 48 本/分**、接続上限（`MAX_STREAM_MS` = 10 分）まで開き続けると 480 本が流れる（TASK-552 で `test/query-count.test.ts` が計測するようにした）。

イベント（アクセス記録）が発生した時点でフロントへ通知できれば、この空振り 2 本が消える。

## 現状の制約（2026-08-25 にコード確認）

- 記録経路と SSE を握っている Worker は別リクエスト・別 isolate で、プロセス内共有メモリが無い。
- D1 に変更通知（LISTEN/NOTIFY 相当）は無い。
- `site/wrangler.toml` に `durable_objects` の宣言は無い（grep 済み）。合流点になる部品がまだ存在しない。

## 想定する形

1. 記録経路が visit を書いた直後、Durable Object へ「新着 id」を通知する（`waitUntil` で fire-and-forget にして計測側のレイテンシへ乗せない）
2. DO は接続中のクライアントへ broadcast する（SSE を DO で保持するか、WebSocket hibernation を使うか）
3. ダッシュボードは通知を受けた周期だけ `summarizeOverview` を引く

## 得失（要検討）

- 得: アイドル時の 48 本/分が 0 になる。
- 失: 計測を受ける経路に DO への往復が乗る。DO 自体の運用コスト・障害時の縮退（DO が落ちたらポーリングへ戻すのか）を決める必要がある。
- 変わらない: `summarizeOverview` の 4 本は既に「新着があった周期だけ」なので push 化しても減らない。**削れるのは空振りの 2 本だけ**であり、そのために DO を 1 個増やすかどうかが判断の中心。

## 着手前に決めること

- DO を入れる価値が「48 本/分の削減」に見合うか。D1 の読み取り課金・無料枠に照らして実数で判断する。
- 縮退方針。DO が使えないときにポーリングへフォールバックするなら、両方の経路を保守することになる。
- SSE のまま DO で保持するか、WebSocket（hibernation 対応）へ変えるか。

## 背景

TASK-552（クエリ本数テストへ SSE の周期コストを載せる）の作業中にユーザーから指摘を受けた。552 は計測のみで、配管は変えていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 上記「着手前に決めること」3 点に結論が出ている
- [x] #2 見送る場合は理由が Notes に実数付きで残っている（アイドル時の D1 行数・CPU・実運用での実測）
- [ ] #3 push 化する場合はアイドル時のクエリ本数が 0 になっていることを test/query-count.test.ts 相当の形で確認できる（採用した場合のみ）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 結論: Durable Object 化は見送る

「48 本/分」はクエリ**本数**の話で、D1 の課金軸ではない。D1 は**読み取り行数・書き込み行数・ストレージ**の 3 つだけで課金し、クエリ本数は課金対象外（https://developers.cloudflare.com/d1/platform/pricing/ ）。空振り 2 本が実際に読む行数を測ったところ、DO を 1 個増やす理由になる規模ではなかった。

### 着手前に決めること 1: DO を入れる価値が 48 本/分の削減に見合うか → 見合わない

**アイドル 1 周期の実測（100,000 行の events に対し、miniflare の D1 で `meta.rows_read` を計測）**

| クエリ | rows_read |
|---|---|
| `SELECT MAX(id) FROM events` | 1 |
| `SELECT ... WHERE id > ? AND NOT bot ORDER BY id LIMIT 50`（新着なし） | 1 |

合計 **2 行/周期**。行数は表のサイズに依らない（id は主キー、`id > ?` はインデックスシーク）。

- タブ 1 枚を開きっぱなしにしたときの読み取り行数: 48 行/分 = 2,880 行/時 = **69,120 行/日**
- Workers Free の無料枠 5,000,000 行/日 の **1.4%**、Workers Paid の 250 億行/月 に対しては 0.0003%
- 超過単価 $0.001 / 100 万行 なので、24 時間開きっぱなしでも **月あたり 0.2 セント**

**Workers 側の実測（本番 observability、2026-08-18〜08-25 の 7 日間、`GET /dashboard/stream` に絞った集計）**

- invocation 924 件、CPU 合計 61,022 ms ≈ **61 CPU 秒 / 7 日**（月換算 261 CPU 秒 = 無料枠 30,000,000 CPU-ms の **0.87%**）
- ストリーミングの待ち時間は課金対象外（Workers は wall clock ではなく CPU 時間で課金し、HTTP 応答の wall clock 上限は無い。https://developers.cloudflare.com/workers/platform/pricing/ ）
- 完走した invocation の平均 wall は 598 秒で、`MAX_STREAM_MS` の 10 分どおりに動いている

対して DO を入れると、記録経路（＝計測を受ける側）に DO への往復が乗り、DO 自身の requests / duration / storage という課金軸が増え、経路が 1 本増える。**削れるのは月 0.2 セント・CPU 0.87% 相当の空振りだけ**なので、割に合わない。

### 着手前に決めること 2: 縮退方針 → 決める必要が無くなった

DO を入れないので二重経路は生じない。仮に入れるなら「DO が落ちたらポーリングへ戻す」が必須で、その時点でポーリング経路も保守し続けることになり、削減分（上記）を上回る保守コストになる。この非対称性自体が見送りの根拠のひとつ。

### 着手前に決めること 3: SSE のままか WebSocket か → SSE のまま

DO を入れないので変更しない。EventSource の自動再接続（`Last-Event-ID` による再開）に乗っているのは、下の exceededCpu の件で実質的に助けられてもいる。

## 副産物: /dashboard/stream の exceededCpu

7 日間の `befold` の invocation 2,041 件のうち **714 件が `exceededCpu`、その全件が `GET /dashboard/stream`**。2026-08-21 の約 9 時間に集中し、平均 CPU 11.6 ms・平均 wall 17〜30 秒で切れている。他の日の `ok` は 274 ms の CPU で 10 分を完走しているので恒常的な上限ではない。**TASK-555 として分離して起票した**（このタスクのスコープ外）。

## 未確認のまま残すこと

- **Workers のプラン。** `/user/subscriptions` には "Teams Free Base" と "R2 Paid" しか無く "Workers Paid" の行は無い。一方で完走した invocation が 274〜461 ms の CPU を使えている（Free の上限は 10 ms）ため、実測からは Paid（Standard）と読める。断定はしない。上の見送り判断は Free / Paid のどちらでも成り立つ（Free の 5M 行/日に対して 1.4%）。
- **D1 の 1 invocation あたりクエリ本数上限**（Free 50 / Paid 1,000、https://developers.cloudflare.com/d1/platform/limits/ ）。10 分 × 2.5 秒周期 = 240 周期でアイドルでも 480 本になり、**Free だと上限を超える**。上で Paid と読んでいるので現状は問題にならないが、`POLL_INTERVAL_MS` を縮める・`MAX_STREAM_MS` を延ばす変更をするときはこの上限が先に当たる。この見積もりは実測ではなくドキュメントの数値。

## 実測に使った手順

- rows_read: `site/test/` に使い捨ての vitest を置き、100,000 行を投入して `meta.rows_read` を読んだ（計測後に削除。リポジトリには残していない）
- 本番の CPU / outcome: Workers observability の calculations ビュー（`$metadata.service = befold`、`$metadata.trigger = GET /dashboard/stream` でグループ化）。observability のログはサンプリングされうるので、件数は下限として読む
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DO 化は見送る。空振り周期が実際に読むのは 2 行/周期（100,000 行の表で実測）で、タブ 1 枚を 24 時間開いても 69,120 行/日＝Free 枠の 1.4%・月 0.2 セント相当。本番 7 日間の /dashboard/stream の CPU 合計も 61 秒（月換算で無料枠の 0.87%）だった。削減できる量に対して DO の追加経路・課金軸・縮退設計が見合わない。調査中に判明した exceededCpu 714 件は TASK-555 へ分離した。
<!-- SECTION:FINAL_SUMMARY:END -->
