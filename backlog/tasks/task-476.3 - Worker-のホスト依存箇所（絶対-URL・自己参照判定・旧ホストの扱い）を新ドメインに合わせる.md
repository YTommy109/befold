---
id: TASK-476.3
title: Worker のホスト依存箇所（絶対 URL・自己参照判定・旧ホストの扱い）を新ドメインに合わせる
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 06:16'
labels:
  - site
dependencies:
  - TASK-476.1
parent_task_id: TASK-476
priority: high
type: chore
ordinal: 101300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Worker のコードには、単一ホスト前提の箇所と旧ホストをハードコードした箇所が残っている。ADR 0007 の決定 2 / 決定 6 の実装。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

対象（実測）:
- `site/src/views/shared.tsx:13` `DOWNLOAD_URL = https://befold.tommy109.workers.dev/download` — site 側で唯一のハードコード絶対 URL。**正規オリジンの定数から組む形へ変える**（ADR 0007 の決定 6。ホスト名リテラルをコード中に散らさない）。
- `site/src/lib/referrer.ts:44` `if (host === selfHost)` — 自己ホストが 1 つ前提。呼び出し元（`site/src/events.ts:46-50`）はリクエストホストを渡している。**引数型を自己ホスト集合へ変え、単一文字列を渡せない形にする**。集合には本番・staging の新旧 4 ホストを入れる。集合と正規オリジンは `site/src/lib` の同じ定数から引く。
- 旧ホストのリダイレクトは **LP（`/`）と `/features` のみを対象とする肯定列挙**で実装する（ADR 0007 の決定 2）。「appcast と /dl/ を除く」という否定列挙は取らない — 新しい機械向けパスを足したときに黙って壊れる。
- `/download` はリダイレクトしない。LP 由来のダウンロード計測（`source:"lp"`、`site/src/routes/public.tsx:42-55`）が 301 を挟んで別ホストへ散るのを避ける。
- canonical / og:url / JSON-LD / robots / sitemap（`site/src/views/landing.tsx`, `features.tsx`, `src/routes/public.tsx:106-128`）はリクエスト origin 由来。旧ホストの HTML ルートを 301 で送ることで重複コンテンツを解消するため、origin 由来のままでよい（staging で正しく動く性質を壊さない）。

注意:
- 決定 6 は移行と同じデプロイに入れる。後回しにすると、その間の新旧ホスト間の遷移が外部参照元として D1 に記録され、参照元の集計（`site/src/analytics.ts:424`）に断層が残る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ダウンロードリンクが配信ホストに依存せず、新旧どちらのホストで開いても同一ホスト内の /download を指す
- [ ] #2 resolveReferrer の引数が自己ホスト集合になっており、単一ホスト文字列を渡す旧実装へ戻せない形になっている
- [ ] #3 新旧ホスト間の遷移が参照元として記録されない（本番・staging の新旧 4 ホストをユニットテストで検証）
- [ ] #4 旧ホストで /appcast.xml・/appcast-develop.xml・/dl/... が 301 ではなく 200 を返すことをテストで担保している
- [ ] #5 旧ホストのリダイレクトが対象パスの肯定列挙で実装されており、列挙外のパスはリダイレクトされない
- [ ] #6 旧ホストの /download がリダイレクトされず、source:"lp" の計測が従来どおり記録される
<!-- AC:END -->
