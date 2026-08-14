---
id: TASK-476.3
title: Worker のホスト依存箇所（絶対 URL・自己参照判定・旧ホストの扱い）を新ドメインに合わせる
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 05:49'
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
Worker のコードには、単一ホスト前提の箇所と旧ホストをハードコードした箇所が残っている。

対象（実測）:
- site/src/views/shared.tsx:13 `DOWNLOAD_URL = https://befold.tommy109.workers.dev/download` — LP と JSON からリンクされる定数。相対 URL かリクエスト origin 由来へ。
- site/src/lib/referrer.ts `resolveReferrer(..., selfHost)` — 自己ホストが 1 つ前提。新旧ホストをまたぐ遷移が外部参照元として計上されると、既存の集計軸（TASK-182.6）にノイズが入る。
- canonical / og:url / JSON-LD / robots / sitemap（site/src/views/landing.tsx, features.tsx, src/routes/public.tsx）はリクエスト origin 由来。旧ホストでも生きたままだと重複コンテンツになるため、正規 URL は新ドメインへ固定するか、旧ホストの HTML ルートを 301 で送るかを ADR の決定に従って実装する。
- ADR で「旧ホストの LP を 301 する」と決めた場合、/appcast*.xml と /dl/ を除外すること（除外漏れは更新経路の破壊に直結する）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ダウンロードリンクが配信ホストに依存せず、新旧どちらのホストで開いても同一ホスト内の /download を指す
- [ ] #2 新旧ホスト間の遷移が参照元として記録されない（referrer のユニットテストで新旧両ホストを検証）
- [ ] #3 旧ホストで /appcast.xml・/appcast-develop.xml・/dl/... がリダイレクトされず従来どおり配信されることをテストで担保している
- [ ] #4 canonical / og:url / sitemap が ADR の決定どおりの URL を返し、既存テストが新ドメインに合わせて更新されている
<!-- AC:END -->
