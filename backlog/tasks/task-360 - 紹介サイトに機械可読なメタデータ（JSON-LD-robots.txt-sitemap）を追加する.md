---
id: TASK-360
title: 紹介サイトに機械可読なメタデータ（JSON-LD / robots.txt / sitemap）を追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 05:02'
updated_date: '2026-08-08 05:33'
labels:
  - site
dependencies:
  - TASK-358
priority: medium
ordinal: 622000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトは現在、機械可読なメタデータを一切持っていない。ルートは / , /download , /appcast.xml , /appcast-develop.xml , /healthz のみで (site/src/routes/public.tsx:10-23, site/src/index.ts:13)、robots.txt・sitemap.xml・JSON-LD 構造化データのいずれも存在しない（site/src と site/public を robots|sitemap|ld\+json|schema.org で grep してヒットゼロ）。

方針の根拠（2026-08 調査）:
- llms.txt は非公式提案で、OpenAI・Google・Anthropic・Meta・Mistral のいずれも本番システムで読むと公式表明していない。Google は 2026-06-15 に Search / AI Overviews に影響しないと明言。公開済み llms.txt の 97% は AI からのリクエストがゼロという計測がある。効果が確認されているのは開発者向けドキュメントサイトでの実行時取得のみで、1 枚の LP である befold の配布サイトには当てはまらない。
- IETF AIPREF WG の vocab / attach ドラフトはまだ RFC になっておらず、かつ AI への opt-out 語彙なので、知られたい側である befold には用がない。
- 一方 schema.org の構造化データは Google も AI 検索も実際に消費している既存規格であり、ここが未実装。

そのため本タスクでは llms.txt は対象外とし、JSON-LD・robots.txt・sitemap.xml を入れる。llms.txt の要否は、TASK-359 の analytics 再設計で AI クローラの UA が可視化されてから実測で判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ランディングページに SoftwareApplication の JSON-LD が埋め込まれ、operatingSystem に macOS、applicationCategory、downloadUrl が含まれる
- [x] #2 JSON-LD の記述内容が本文・title・og の文言と矛盾しない（特に対応 OS が macOS 専用であること。TASK-358 の文言修正と整合させる）
- [x] #3 robots.txt を配信し、/dashboard をクロール対象から外したうえで sitemap.xml を参照している
- [x] #4 sitemap.xml を配信し、公開ページのみを列挙している（/dashboard や /healthz を含めない）
- [x] #5 各エンドポイントが 200 と正しい Content-Type を返すテストがある
- [x] #6 llms.txt は本タスクでは追加しない（判断の根拠は Description に記載）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Landing の head に SoftwareApplication の JSON-LD を埋め込む（operatingSystem: macOS 14 以降 / applicationCategory / downloadUrl / offers price 0）
2. publicRoutes に /robots.txt を追加（Disallow: /dashboard、Sitemap 参照）
3. publicRoutes に /sitemap.xml を追加（公開ページ / のみ列挙）
4. test/public.test.ts に 200 と Content-Type、および JSON-LD の内容を検証するテストを追加
5. llms.txt は追加しない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landing の head に SoftwareApplication の JSON-LD（operatingSystem: 'macOS 14 (Sonoma) or later'、applicationCategory: DeveloperApplication、downloadUrl、offers price 0、description は PAGE_DESCRIPTION を再利用）を追加。robots.txt / sitemap.xml は静的アセットではなく publicRoutes のルートとして実装した（origin をリクエストから取り、staging が本番 URL を指さないようにするため。og:url と同じ方針）。sitemap は公開ページ / のみ。recordEvent は呼ばないので visit を汚染しない。llms.txt は Description の根拠どおり追加していない。検証: npx vitest run で 57 passed（新規 7 件: JSON-LD 2 / robots・sitemap 3 / 対象 OS 2）、npx tsc --noEmit エラーなし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布サイトに SoftwareApplication の JSON-LD、/robots.txt（/dashboard を除外し sitemap を参照）、/sitemap.xml（公開ページのみ）を追加した。robots/sitemap は origin をハードコードしないよう Worker ルートとして配信。ステータスコード・Content-Type・JSON-LD 内容・visit を記録しないことをテストで検証（vitest 57 件 pass、tsc エラーなし）。llms.txt は当初方針どおり対象外。
<!-- SECTION:FINAL_SUMMARY:END -->
