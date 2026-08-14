---
id: TASK-476.2
title: Workers Custom Domain と DNS を設定し新ドメインで疎通させる
status: To Do
assignee: []
created_date: '2026-08-13 14:20'
updated_date: '2026-08-14 06:16'
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
Cloudflare の degino.com ゾーンに `befold.degino.com` と `staging.befold.degino.com` の Workers Custom Domain を設定し、`site/wrangler.toml` に routes を記述する。ホスト名は ADR 0007 の決定 4 で確定済み。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

注意点:
- Custom Domain 設定時に DNS レコードは Cloudflare 側が自動作成する。既存の degino.com の他レコードを壊さないこと。
- **`workers_dev = true` を本番・staging とも明示的に残す。** routes を書くと `workers_dev` は次回デプロイで `false` と推論される仕様があるため（Cloudflare「workers.dev」ドキュメント）、明示指定しないと旧ホストが落ちる。旧ホストが落ちると出荷済みアプリの更新チェックが止まる（ADR 0007 の決定 1）。
- assets / d1_databases / observability は環境非継承キー。staging 側に routes を足すときも既存の再指定を崩さない。
- `site/wrangler.toml:6-8` と `site/src/routes/dashboard.tsx:16` のコメントは「workers.dev には Access を設定できない」と書いているが、これは現在の Cloudflare ドキュメントに照らして誤り。書き換える際に事実を訂正すること（保護面を 1 つに畳む判断そのものは ADR 0007 の決定 5 のとおり変えない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 https://befold.degino.com/ で LP が表示され、/appcast.xml と /download が本番と同じ内容を返す
- [ ] #2 旧 https://befold.tommy109.workers.dev/appcast.xml が引き続き 200 を返す
- [ ] #3 staging が https://staging.befold.degino.com で公開され、site-staging ワークフローの出力 URL が実際の公開先と一致している
- [ ] #4 routes 追加後のデプロイでも本番・staging の workers.dev ホストが生きていることを実測で確認している
- [ ] #5 site/wrangler.toml のコメントが現状に合わせて書き換えられ、workers.dev に Access を張れないという誤った記述が残っていない
<!-- AC:END -->
