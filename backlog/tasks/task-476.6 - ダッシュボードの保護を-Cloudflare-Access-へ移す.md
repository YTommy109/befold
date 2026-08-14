---
id: TASK-476.6
title: ダッシュボードの保護を Cloudflare Access へ移す
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 06:17'
labels:
  - site
dependencies:
  - TASK-476.1
  - TASK-476.2
  - TASK-476.3
parent_task_id: TASK-476
priority: low
type: chore
ordinal: 101600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
独自ドメイン配下になることで Cloudflare Access が使えるようになる。ADR 0007 の決定 5 で「Access へ移す」と確定済み（本タスクの実施は確定。条件付きではない）。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

現状は Worker 側の Basic 認証（シークレット DASHBOARD_PASSWORD）で保護している（`site/src/routes/dashboard.tsx:13-29`）。設定ファイルとコード中のコメントは「workers.dev には Access を張れない」を根拠に挙げているが、この前提は現在の Cloudflare ドキュメントに照らして誤り。それでも保護面は新ドメインの 1 つに畳む（2 面あると片方だけ設定が抜ける形で破れる）。

実装:
- 新ドメインの `/dashboard` と `/dashboard/*` を Access の self-hosted アプリケーションで保護する。**ワイルドカードは親パスを含まないため 2 本の指定が必要**（Cloudflare「Access application paths」）。
- Worker 側で Access の JWT（`Cf-Access-Jwt-Assertion`）を検証する。Access を張っても Worker が素通しでは、経路を迂回された場合に無防備になる。
- **旧ホスト（workers.dev）の `/dashboard` は 404 を返す。** 301 で新ドメインへ送る形は取らない（ダッシュボードは新ドメイン専用とする）。
- Basic 認証は Access の動作を実測で確認するまで残し、確認後に削除する。`DASHBOARD_PASSWORD` シークレットも同時に削除する。
- SSE（`site/src/routes/dashboard.tsx:37-96` の `/dashboard/stream`）が Access 経由で動くことを実測で確認する。

未確定: Access のポリシー内容（許可する識別子・セッション長）は本タスクで決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 新ドメインの /dashboard が Access で保護され、認証後に集計と SSE が従来どおり動作する
- [ ] #2 /dashboard と /dashboard/* の両方が保護されている（親パスがワイルドカードから漏れていない）
- [ ] #3 Worker 側で Access JWT を検証しており、JWT 未提示のリクエストが通らない
- [ ] #4 旧ホストの /dashboard が 404 を返す
- [ ] #5 Basic 認証の実装・DASHBOARD_PASSWORD シークレット・テスト・ドキュメントの記述が整理されている
- [ ] #6 Access のポリシー内容（許可する識別子・セッション長）が Implementation Notes に記録されている
<!-- AC:END -->
