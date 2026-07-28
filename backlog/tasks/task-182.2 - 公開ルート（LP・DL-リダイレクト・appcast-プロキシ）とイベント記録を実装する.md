---
id: TASK-182.2
title: 公開ルート（LP・DL リダイレクト・appcast プロキシ）とイベント記録を実装する
status: To Do
assignee: []
created_date: '2026-07-28 13:35'
labels: []
dependencies: []
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: high
ordinal: 259000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GET / の配布 LP（htmx + hyperscript）、GET /download の計測付き 302 リダイレクト（GitHub Releases の DMG へ）、GET /appcast.xml と /appcast-develop.xml の計測付きプロキシ配信を実装する。イベントは zod で検証し ctx.waitUntil で best-effort に D1 へ記録する。visitor_day は sha256(ip+ua+日付) で日次ユニーク推定し生 IP は保存しない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 / が配布 LP を返し visit を記録する
- [ ] #2 /download が DMG へ 302 リダイレクトし download を記録する
- [ ] #3 /appcast.xml・/appcast-develop.xml が GitHub の appcast をプロキシし update_check を記録する
- [ ] #4 D1 記録の失敗時もレスポンスは成功する（best-effort）
- [ ] #5 生 IP・完全 UA は保存されず visitor_day ハッシュは決定的である
<!-- AC:END -->
