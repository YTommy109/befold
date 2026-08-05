---
id: TASK-182.2
title: 公開ルート（LP・DL リダイレクト・appcast プロキシ）とイベント記録を実装する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:35'
updated_date: '2026-07-28 17:06'
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
- [x] #1 / が配布 LP を返し visit を記録する
- [x] #2 /download が DMG へ 302 リダイレクトし download を記録する
- [x] #3 /appcast.xml・/appcast-develop.xml が GitHub の appcast をプロキシし update_check を記録する
- [x] #4 D1 記録の失敗時もレスポンスは成功する（best-effort）
- [x] #5 生 IP・完全 UA は保存されず visitor_day ハッシュは決定的である
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. src/lib/visitor.ts: sha256(ip+ua+YYYY-MM-DD) の visitor_day ハッシュと、OS/UA 要約（生 UA は保存しない）を実装する
2. src/events.ts: zod 検証 → D1 INSERT を ctx.waitUntil で best-effort 実行する recordEvent を実装する（失敗は握りつぶしてレスポンスに影響させない）
3. src/views/landing.tsx: 既存 docs/index.html の LP を Hono JSX へ移植し、CSS/JS/画像は site/public/ に配置して wrangler の assets バインディングで配信する
4. src/routes/public.ts:
   - GET / → LP を返し visit を記録
   - GET /download → GitHub API で最新リリースの .dmg アセットを解決し 302、download を記録（API 失敗時は releases/latest ページへフォールバック）
   - GET /appcast.xml, /appcast-develop.xml → GitHub の appcast をプロキシし update_check を記録（上流失敗時は 502）
5. test/: 各ルートの応答、best-effort 挙動（D1 失敗時も 200/302）、visitor_day の決定性と生 IP/UA 非保持を検証する
6. tsc --noEmit / vitest run / wrangler dev の手動確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証ログ:
- `vitest run` → 17 tests passed（LP・/download・appcast 双方・502・best-effort・プライバシー）
- `tsc --noEmit` → エラーなし
- `wrangler dev --local` 実機確認: / 200 / style.css 200 / images/screenshot-1.png 200 / download 302 → https://github.com/YTommy109/befold/releases/download/v1.10.0/befold-v1.10.0.dmg / appcast.xml 200（実 Sparkle XML）
- `wrangler d1 execute --local` で events を確認: visit / download / update_check が記録され、生 IP・完全 UA は列に存在せず visitor_day はハッシュのみ

設計上の判断:
- LP は htmx/hyperscript を使わず、既存 docs/index.html の vanilla JS（言語切替・カルーセル）をそのまま移植した。LP はサーバ駆動の部分更新を持たないため htmx の利点がなく、依存を増やさない方が単純と判断。htmx は 182.3 のダッシュボード（SSE）で導入する。
- /download は DMG 名にバージョンが入る（befold-vX.Y.Z.dmg）ため releases/latest/download を使えない。GitHub API の latest release から .dmg アセットを解決し、失敗時は releases/latest ページへフォールバックする（導線を切らさない）。
- LP の CSS/JS/画像は wrangler の [assets] バインディング（public/）で配信。docs/ からのコピーは 182.5 で docs/ 側を縮退させて解消する。
- @cloudflare/vitest-pool-workers v0.18 では cloudflare:test の fetchMock が撤去されたため、上流 fetch のモックは vi.stubGlobal で行う。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
公開ルート 3 系統（GET / の配布 LP、GET /download の計測付き 302、GET /appcast.xml・/appcast-develop.xml のプロキシ）と、zod 検証 + ctx.waitUntil による best-effort なイベント記録を実装した。visitor_day は sha256(ip+ua+UTC 日付) で決定的に生成し、生 IP・完全 UA は保存しない（OS/UA は要約のみ）。vitest 17 件と wrangler dev での実 GitHub 相手の疎通、ローカル D1 の記録内容で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
