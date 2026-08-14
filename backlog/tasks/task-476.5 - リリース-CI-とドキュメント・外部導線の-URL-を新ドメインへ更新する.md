---
id: TASK-476.5
title: リリース CI とドキュメント・外部導線の URL を新ドメインへ更新する
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 05:49'
labels:
  - site
dependencies:
  - TASK-476.2
parent_task_id: TASK-476
priority: medium
type: chore
ordinal: 101500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布ワークフローと外部から見える文書の URL を新ドメインへ揃える。

対象（実測）:
- .github/workflows/release.yml:274 `download_url_prefix="https://befold.tommy109.workers.dev/dl/${tag_name}/"` — 生成される appcast の enclosure URL。ここを変えると新規リリースの DMG 取得先が新ドメインになる。過去リリース分の enclosure は旧ホストのまま残るため、旧ホストの /dl/ は止められない。
- .github/workflows/site-staging.yml:77 の案内 URL
- README.md、docs/index.html（GitHub Pages のリダイレクトページ）、docs/dev/development.md、site/README.md
- scripts/analytics-query.sh に URL 参照があれば更新

?ref= 付きリンク（gh-pages / readme）は値を変えない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 リリースワークフローが生成する appcast の enclosure URL が befold.degino.com を指す
- [ ] #2 README・docs・site/README・gh-pages のリダイレクト先が新ドメインになっている（?ref= の値は変更しない）
- [ ] #3 旧ホストの /dl/ を維持する必要がある理由が release.yml かドキュメントにコメントとして残っている
- [ ] #4 markdownlint-cli2 が通る
<!-- AC:END -->
