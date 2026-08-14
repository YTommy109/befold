---
id: TASK-476.2
title: Workers Custom Domain と DNS を設定し新ドメインで疎通させる
status: To Do
assignee: []
created_date: '2026-08-13 14:20'
updated_date: '2026-08-14 05:49'
labels:
  - site
dependencies:
  - TASK-476.1
parent_task_id: TASK-476
priority: high
type: chore
ordinal: 101200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cloudflare の degino.com ゾーンに befold.degino.com（および ADR で決めた staging ホスト）の Workers Custom Domain を設定し、site/wrangler.toml に routes を記述する。

注意点:
- Custom Domain 設定時に DNS レコードは Cloudflare 側が自動作成する。既存の degino.com の他レコードを壊さないこと。
- `workers_dev = true` は残す（ADR の決定に従う）。旧ホストを落とすと出荷済みアプリの更新チェックが止まる。
- assets / d1_databases / observability は環境非継承キー。staging 側に routes を足すときも既存の再指定を崩さない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 https://befold.degino.com/ で LP が表示され、/appcast.xml と /download が本番と同じ内容を返す
- [ ] #2 旧 https://befold.tommy109.workers.dev/appcast.xml が引き続き 200 を返す
- [ ] #3 staging ホストが ADR の決定どおりに設定され、site-staging ワークフローの出力 URL が実際の公開先と一致している
- [ ] #4 site/wrangler.toml のコメント（独自ドメインを使わない理由）が現状に合わせて書き換えられている
<!-- AC:END -->
