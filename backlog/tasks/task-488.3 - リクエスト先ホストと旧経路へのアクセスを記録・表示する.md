---
id: TASK-488.3
title: リクエスト先ホストと旧経路へのアクセスを記録・表示する
status: To Do
assignee: []
created_date: '2026-08-16 02:07'
labels: []
milestone: m-7
dependencies:
  - TASK-488.1
parent_task_id: TASK-488
priority: medium
ordinal: 725000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488 の計測範囲のうち、配布 URL の一本化（TASK-489 / m-8）が判断材料として必要とするもの。もとは TASK-489.2 として起票したが、計測基盤の変更は 488 側に集約する（TASK-489.2 はアーカイブ済み）。

## なぜ必要か

配布サイトは 3 世代の URL すべてで応答している（GitHub Pages / `befold.tommy109.workers.dev` / `befold.degino.com`。2026-08-16 実測で全て稼働中）。旧世代を止めてよいかは「旧ホストを叩くクライアントがゼロか」で決まるが、`events` テーブルにはリクエスト先ホストの列が無いため（`site/schema/schema.sql:5-26`）、**今は数えられない**。ADR 0007 は停止条件をこの観測に置いているので（`docs/adr/0007-distribution-site-custom-domain.md:117-118`）、観測できないままでは条件を永久に判定できない。

## 記録したいもの

1. **リクエスト先ホスト**（旧ホスト `befold.tommy109.workers.dev` / 正規ホスト / staging）。`update_check` は既に記録されている（`site/src/routes/public.tsx:146`）ので、ホストの次元を足せば旧ホスト分を分離できる
2. **R2 ミスによる GitHub フォールバックの発生**。`site/src/routes/public.tsx:73-76` の 302（`/dl/`）、`site/src/lib/github.ts:10-12` の appcast プロキシ、`/download` の GitHub API 経路。ここが 0 でないうちは GitHub 側を止められない

## 既に取れているもの（作り直さないこと）

**GitHub Pages からの流入は既に記録されている。** `docs/index.html` は `?ref=gh-pages` を付けて遷移し、`resolveReferrer`（`site/src/lib/referrer.ts`）は `?ref=` を最優先で採用する。その doc コメントには「GitHub Pages は静的ホスティングのためサーバーサイドリダイレクトができず meta refresh / JS になり Referer は取りこぼしが出る。明示パラメータなら影響を受けずに数えられる」とあり、**gh-pages の計測がこの仕組みの動機**。参照元別の内訳もダッシュボードに既にある（`site/src/analytics.ts:424` の `breakdown(db, referrer)`）。

足りないのは人間とロボットの分離だけで、これは TASK-488.2 の対象。したがってこのサブタスクで `?ref=gh-pages` の記録を作り直す必要はない。

## 観測できないもの

GitHub 直の appcast（`https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml`）を見ている v1.10.0 以前のクライアントは、サイトを経由しないため Worker では観測できない。GitHub のリリースアセットのダウンロード数 API など別手段の可否を調べ、結果を記録する。

## 制約

- スキーマ変更は TASK-488.1 と重複させない（同じマイグレーションにまとめるか後続で足すかを判断する）
- ボット判定は既存の `ua_summary` の `bot:` 接頭辞を流用する（`site/src/lib/visitor.ts:104-123`）
- `summarize()` のクエリ数上限テスト（`site/test/query-count.test.ts:35`）に触れないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 リクエスト先ホスト（旧ホスト / 正規ホスト）が events に記録される
- [ ] #2 旧ホストへのアクセス数が人間とロボットに分けてダッシュボードで確認できる
- [ ] #3 R2 ミスによる GitHub フォールバックの発生が観測できる
- [ ] #4 GitHub 直 appcast を見ているクライアントの観測可否と方法が調査結果として記録されている
- [ ] #5 ?ref=gh-pages の既存の記録経路を作り直していない
- [ ] #6 TASK-488.1 のスキーマ変更と列設計が重複していない
- [ ] #7 site の vitest と typecheck が通る
<!-- AC:END -->
