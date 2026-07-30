---
id: TASK-201
title: 配布サイトに OGP を追加し SNS 共有時のカード表示を整える
status: Done
assignee: []
created_date: '2026-07-30 15:25'
updated_date: '2026-07-30 15:58'
labels: []
dependencies: []
priority: medium
ordinal: 284000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
https://befold.tommy109.workers.dev/ を SNS に投稿すると、og:*/twitter:* が一切ないため意図しない切り抜きのカードになる。1200x630 の専用画像を用意し、大判カード（summary_large_image）で表示されるようにする。設計: docs/superpowers/specs/2026-07-31-site-ogp-design.md / 計画: docs/superpowers/plans/2026-07-31-site-ogp.md
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 トップページの HTML に og:type/og:site_name/og:title/og:description/og:url/og:image/og:image:width/og:image:height/og:image:alt/twitter:card と canonical が出力される
- [x] #2 og:url と og:image がリクエストの origin から組み立てられ、ホストが変わればその値も変わる（ハードコードでない）
- [x] #3 og:title と og:description が既存の title / meta description と同一文字列である
- [x] #4 site/public/images/ogp.png が 1200x630 で、実環境の /images/ogp.png が 200 と image/png を返す
- [x] #5 twitter:card が summary_large_image である
- [x] #6 OGP 画像を作り直せる HTML テンプレートと生成手順が site/tools/ に残っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: site/src/views/landing.tsx に PAGE_TITLE / PAGE_DESCRIPTION 定数を切り出し、og:*/twitter:card/canonical を追加。Landing を FC<{origin: string}> にし、site/src/routes/public.tsx で new URL(c.req.url).origin を渡すことで絶対 URL を組み立てる（ホスト名をハードコードしないため）。OGP 画像は site/tools/ogp-template.html をヘッドレス Chrome で 1200x630 撮影した静的 PNG。

判断: 当初計画の「/images/ogp.png が 200 で返る」ユニットテストは取りやめた。[assets] の静的配信が @cloudflare/vitest-pool-workers 上で再現される保証がなく、通っても本番の保証にならないため。代わりに sips での寸法検証と staging 実環境での curl 確認に分解した。

検証: npm run typecheck エラーなし。npm test 48/48 PASS（OGP 関連 4 件を新規追加、うち 1 件は別ホストで og:url を検証しハードコードを検出できる形）。staging (https://befold-staging.tommy109.workers.dev) へデプロイし、og:url/og:image が staging のホスト名を指すこと、/images/ogp.png が 200 / image/png を返すことを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布サイトのトップページに OGP / Twitter カードのメタタグと専用の 1200x630 画像を追加し、SNS 共有時に大判カードが意図どおり表示されるようにした。絶対 URL はリクエストの origin から組み立てるため staging でも正しい URL が出る。画像は site/tools/ に生成テンプレートと手順を残して作り直せるようにした。
<!-- SECTION:FINAL_SUMMARY:END -->
