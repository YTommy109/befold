---
id: TASK-476.5
title: リリース CI とドキュメント・外部導線の URL を新ドメインへ更新する
status: Done
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 07:11'
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
- [x] #1 リリースワークフローが生成する appcast の enclosure URL が befold.degino.com を指す
- [x] #2 README・docs・site/README・gh-pages のリダイレクト先が新ドメインになっている（?ref= の値は変更しない）
- [x] #3 旧ホストの /dl/ を維持する必要がある理由が release.yml かドキュメントにコメントとして残っている
- [x] #4 markdownlint-cli2 が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ADR 0007 との整合（TASK-476.1 で確認）:

- 決定 3 により `.github/workflows/release.yml:274` の `download_url_prefix` は新ドメインへ切り替える（既存 AC #1 のとおりで矛盾なし）。
- `docs/index.html` の GitHub Pages リダイレクト shim を新ドメインへ向け直すか撤去するかは **ADR 0007 で未確定**とした。本タスクで決めること。向け直す場合 `?ref=gh-pages` の値は変えない。
- 旧ホストの `/dl/` を止められない理由は ADR 0007 の Context（配信済み appcast の enclosure が旧ホストを指す）。AC #3 のコメントはこの ADR を参照する形にしてよい。

実装（実測）:
- .github/workflows/release.yml:280 の download_url_prefix を https://befold.degino.com/dl/${tag_name}/ へ変更。この値は :295 / :304 の generate_appcast --download-url-prefix にそのまま渡り、enclosure URL になる（grep で用途 3 箇所を確認）。同 :274-279 に、旧ホストの /dl/ を止められない理由（配信済み appcast の enclosure が旧ホストを指す）と ADR 0007 決定 1/3 への参照をコメントで残した。
- README.md:6,41 / docs/dev/development.md:137,141 / docs/index.html:7,14,15,48,54 を新ドメインへ。?ref=readme・?ref=gh-pages の値は変更していない。
- site/README.md:8,187 の公開 URL を新ドメインにし、旧 URL が併存する旨と ADR 0007 へのリンクを併記。
- .github/workflows/site-staging.yml:77-78 は既に新ドメインを先頭に案内しており変更不要。scripts/analytics-query.sh に URL 参照は無かった（grep http でヒット 0）。

決定（ADR 0007 で未確定だった点）: docs/index.html の GitHub Pages リダイレクト shim は撤去せず、新ドメインへ向け直す。gh-pages の URL は外部から参照されうるうえ、shim を消すと 404 になり ?ref=gh-pages の計測も途切れるため。

検証: markdownlint-cli2 で 71 ファイル 0 issues。enclosure URL はリリース実行を伴うため未実測で、根拠は上記の変数受け渡しのコード参照。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
リリース CI の appcast enclosure prefix と README・docs・site/README・gh-pages shim の URL を befold.degino.com へ更新し、旧ホストの /dl/ を維持する理由を release.yml のコメントに残した。markdownlint-cli2 は 0 issues。
<!-- SECTION:FINAL_SUMMARY:END -->
