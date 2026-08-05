---
id: TASK-182.3
title: 分析ダッシュボード（Access 保護・集計・SSE リアルタイム）を実装する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:35'
updated_date: '2026-07-29 11:30'
labels: []
dependencies: []
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: high
ordinal: 260000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GET /dashboard を Cloudflare Access で所有者のみに保護し、日別 DL・バージョン別内訳・国別・OS 別・update_check 数を集計して htmx で描画する。GET /dashboard/stream で D1 ポーリング型 SSE（2〜3 秒間隔で id>lastSeenId の新着を push）を実装し、htmx SSE 拡張でカウンタと最新イベント一覧を更新する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /dashboard が Cloudflare Access で所有者のみ閲覧できる
- [x] #2 集計（日別/バージョン別/国別/OS 別/update_check）が表示される
- [x] #3 /dashboard/stream の SSE で新着イベントがリアルタイムに反映される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. src/analytics.ts: 集計クエリ（日別 DL・バージョン別・国別・OS 別・update_check 数・ユニークビジター）を GROUP BY で実装する
2. src/routes/dashboard.tsx: Cloudflare Access 前提の保護ルートを実装する
   - requireAccess ミドルウェア: Cf-Access-Jwt-Assertion ヘッダ不在なら 403（workers.dev 直叩きによる Access バイパス対策の多層防御）
   - GET /dashboard: 集計をサーバレンダリング
   - GET /dashboard/stream: D1 ポーリング型 SSE（2.5s 間隔で id > lastSeenId の新着を push、Last-Event-ID で再開）
3. src/views/dashboard.tsx: 集計テーブルと最新イベント一覧。EventSource で SSE を受信して DOM 更新
4. wrangler.toml: workers_dev = false（Access が効かない *.workers.dev 経由の到達を塞ぐ）
5. test/: Access ヘッダ無しで 403、集計の描画、SSE の初回 push を検証する
6. docs: Cloudflare Access ポリシーの設定手順を記載する
7. tsc --noEmit / vitest run / wrangler dev で確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証ログ:
- `vitest run` → 23 tests passed（Access ヘッダ無し 403 / 有り 200、公開ルートは影響なし、集計の描画、空データ、SSE の after 以降のみ push）
- `tsc --noEmit` → エラーなし
- `wrangler dev --local` 実機確認:
  - /dashboard は Access ヘッダ無しで 403、有りで 200（count-visit=2 / count-download=1 / count-update_check=1 と実データが描画）
  - /dashboard/stream に接続したまま / を叩くと、接続後に発生した id=5 の visit が keep-alive を挟んで push された（リアルタイム反映を実確認）

設計上の判断:
- AC#1 の認可本体は Cloudflare Access のポリシー（所有者メールのみ）で、設定手順は site/README.md に記載した。Worker はポリシーを持たず、Access が付与する Cf-Access-Jwt-Assertion ヘッダの有無だけを見て 403 を返す多層防御とした。
- *.workers.dev には Access が掛からず /dashboard に到達できてしまうため、wrangler.toml で workers_dev = false にして経路自体を塞いだ。
- htmx + SSE 拡張ではなく素の EventSource（約 20 行）で実装した。受信するのは JSON 差分でありサーバ側 HTML 断片の差し替えが不要なため、htmx と拡張を vendoring する必要がない。
- SSE は 2.5s ポーリング、1 接続あたり最大 10 分で自動終了（ブラウザが再接続）。Last-Event-ID とクエリ after の両方で再開位置を受け取る。
- 集計は breakdown() のカラムを固定の union 型に限定し、kind はバインド変数で渡して SQL への外部入力混入を避けた。

【方針変更 2026-07-29】独自ドメインを取得せず *.workers.dev で公開する方針が確定したため、認可方式を Cloudflare Access から Worker 側の Basic 認証へ変更した。
理由: Access のアプリケーションは自アカウントのゾーンのホスト名にしか設定できず、Cloudflare 所有ドメインである workers.dev は保護対象にできないため。
- /dashboard・/dashboard/stream を hono/basic-auth で保護。パスワードはシークレット DASHBOARD_PASSWORD（未設定時は素通しさせず 503）。
- workers_dev = false → true に戻した。
- EventSource はヘッダを設定できないが、ブラウザは認証済みオリジンへ Basic 認証情報を自動送出するため SSE もそのまま動作する（wrangler dev で確認済み）。
- テスト用の認証情報は .dev.vars（gitignore）ではなく vitest.config.ts の miniflare bindings に固定し、クリーンな clone でもテストが通るようにした。
再検証: vitest 25 passed（401/誤パスワード 401/未設定 503/正しい認証 200 を追加）、tsc クリーン、wrangler dev で 401→200・SSE の live push・公開ルート 200 を確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
分析ダッシュボード（GET /dashboard）と D1 ポーリング型 SSE（GET /dashboard/stream）を実装した。集計は種別ごとの合計・ユニーク訪問者・日別 DL(14 日)・バージョン別・国別・OS 別・最新イベント一覧。*.workers.dev で公開する方針のため Cloudflare Access は使えず、認可は Worker 側の Basic 認証（シークレット DASHBOARD_PASSWORD、未設定時は 503）で実装した。vitest 25 件と wrangler dev での実機確認（401/200、集計描画、接続後イベントの live push）で検証済み。設定手順は site/README.md に記載。
<!-- SECTION:FINAL_SUMMARY:END -->
