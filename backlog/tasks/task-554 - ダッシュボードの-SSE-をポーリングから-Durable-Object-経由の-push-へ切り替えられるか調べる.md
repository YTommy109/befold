---
id: TASK-554
title: ダッシュボードの SSE をポーリングから Durable Object 経由の push へ切り替えられるか調べる
status: To Do
assignee: []
created_date: '2026-08-25 02:17'
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
- [ ] #1 上記「着手前に決めること」3 点に結論が出ている
- [ ] #2 push 化する場合はアイドル時のクエリ本数が 0 になっていることを test/query-count.test.ts 相当の形で確認できる
- [ ] #3 見送る場合は理由が Notes に実数付きで残っている
<!-- AC:END -->
