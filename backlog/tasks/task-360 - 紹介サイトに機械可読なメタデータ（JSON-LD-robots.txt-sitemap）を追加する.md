---
id: TASK-360
title: 紹介サイトに機械可読なメタデータ（JSON-LD / robots.txt / sitemap）を追加する
status: To Do
assignee: []
created_date: '2026-08-08 05:02'
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
- [ ] #1 ランディングページに SoftwareApplication の JSON-LD が埋め込まれ、operatingSystem に macOS、applicationCategory、downloadUrl が含まれる
- [ ] #2 JSON-LD の記述内容が本文・title・og の文言と矛盾しない（特に対応 OS が macOS 専用であること。TASK-358 の文言修正と整合させる）
- [ ] #3 robots.txt を配信し、/dashboard をクロール対象から外したうえで sitemap.xml を参照している
- [ ] #4 sitemap.xml を配信し、公開ページのみを列挙している（/dashboard や /healthz を含めない）
- [ ] #5 各エンドポイントが 200 と正しい Content-Type を返すテストがある
- [ ] #6 llms.txt は本タスクでは追加しない（判断の根拠は Description に記載）
<!-- AC:END -->
