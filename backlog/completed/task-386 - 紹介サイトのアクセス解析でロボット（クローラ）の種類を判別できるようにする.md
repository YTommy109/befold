---
id: TASK-386
title: 紹介サイトのアクセス解析でロボット（クローラ）の種類を判別できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-09 08:28'
updated_date: '2026-08-09 09:05'
labels: []
dependencies: []
references:
  - site/src/lib/visitor.ts
  - site/src/events.ts
  - site/src/analytics.ts
  - site/src/routes/public.tsx
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
priority: medium
type: feature
ordinal: 643000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
紹介サイトのアクセス解析（Cloudflare Worker → D1 のサーバ側記録方式）は、JS ビーコンを使わないためクローラの訪問も既に events に記録されている。しかし ua_summary を作る summarizeUA が Sparkle / 主要ブラウザ / curl 以外をすべて 'other' へ丸めるため、GPTBot・ClaudeBot・Googlebot などの種類が判別できない。

site/src/analytics.ts:280-282 のコメントは「ua_summary の内訳は AI クローラ（GPTBot / ClaudeBot 等）の到来量を実測するために持つ」と明記しており、意図はあるが実装が追いついていない状態。

新しい列やテーブル、新しい計測経路は不要で、summarizeUA の分類を増やし、ダッシュボードで人間の訪問とロボットの巡回を分けて見せることで目的を満たせる。as_org（request.cf.asOrganization、site/src/events.ts:53）に接続元組織が入っているため、UA を詐称する巡回の裏取り材料も既にある。

前提と裏付け:
- コード参照: 記録本体 site/src/events.ts:27-75、UA 要約 site/src/lib/visitor.ts:43-51、計測ポイント site/src/routes/public.tsx:19,49、robots.txt site/src/routes/public.tsx:106-111（Allow: / なのでクローラは LP を巡回できる）
- 制約: 完全な User-Agent を保存していないため、過去データは遡って分類できない。内訳が出るのは適用日以降のみ。
- 未確認: request.cf.botManagement.verifiedBot を使えばより確実だが、Bot Management 契約に依存し、workers_dev = true の現構成（site/wrangler.toml:9）で取得できるかは実測していない。まず UA 判定で始める。
- 検討事項: /features は現在意図的に非計測（site/src/routes/public.tsx:23-34）。クローラ計測の観点で計測対象に含めるかを判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 summarizeUA が主要な検索クローラ（Googlebot / bingbot 等）と AI クローラ（GPTBot / ClaudeBot / OAI-SearchBot / PerplexityBot 等）を個別の値として返す
- [x] #2 判別できないボットは 'other' に埋もれず、ボットと分かる値（bot-other 等）に分類される
- [x] #3 上記の分類がユニットテストで ON/OFF 両方向（既知ボットの UA / 通常ブラウザの UA）について担保されている
- [x] #4 ダッシュボードで人間の訪問とロボットの巡回が分離して表示され、ロボットは種類別の内訳が見える
- [x] #5 /features を計測対象に含めるかを判断し、その結論と理由を Implementation Notes に記録する
- [x] #6 過去データを遡って分類できないこと（適用日以降のみ内訳が出ること）がダッシュボードの表示または注記から読み取れる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. summarizeUA にボット判定を追加する（ブラウザ判定より前に評価する。Googlebot 等の UA は Chrome/ を含むため）。既知の検索クローラ・AI クローラは 'bot:Googlebot' 等、既知トークンに当たらないボット様 UA（bot/crawler/spider/slurp）は 'bot:other' を返す。ボット値は接頭辞 'bot:' で識別する（値の列挙を集計側と二重管理しないため、SQL は LIKE 'bot:%' で分けられる）。
2. analytics.ts の byUA を uaSplit（人間 / ロボットの件数と、それぞれの内訳）へ置き換える。ua_summary LIKE 'bot:%' で分離し、新しい列・テーブルは作らない（ADR 0004）。
3. ダッシュボードに「人間の訪問 / ロボットの巡回」ブロックを置き、ロボットは種類別の内訳を表示する。分類の適用日以降しか内訳が出ないことを注記する（AC#6）。
4. ユニットテスト: visitor.test.ts に既知ボット UA / 通常ブラウザ UA の両方向、analytics.test.ts に uaSplit の分離、dashboard.test.ts に表示と注記。
5. /features を計測対象に含めるかを判断し Implementation Notes に記録する（AC#5）。

設計判断は ADR 0004（docs/adr/0004-bot-detection-via-user-agent.md）で確定済みのため /review-design は回さない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

ADR 0004 の決定どおり、UA トークン判定でボットを分類した。新しい列・テーブル・計測経路は追加していない。

- `site/src/lib/visitor.ts`: `summarizeUA` にボット判定を追加。既知トークン（AI クローラ 18 種・検索クローラ 6 種・SNS のリンク展開 4 種）は `bot:GPTBot` のように接頭辞付きで返し、既知トークンに当たらないボット様 UA（bot/crawler/spider/scraper/slurp/feedfetcher）は `bot:other` へ落とす。判定はブラウザ判定より**先**に置いた（現行の Googlebot / Applebot の UA は `Chrome/` `Safari/` を含むため、順序を逆にすると人間として計上される。この順序はテストで担保: 「ブラウザ由来のトークンを含むクローラでもブラウザに分類しない」）。
- `BOT_PREFIX` を接頭辞にしたのは、集計側にボット名の一覧を持たせないため。SQL は `ua_summary LIKE 'bot:%'` だけで分離でき、`BOT_TOKENS` を増やしても集計側の同期漏れが構造的に起きない（列挙の二重管理を作らない）。`Applebot-Extended` は `Applebot` より前に置く必要があるため、トークン表は上から順に評価する配列にした。
- `site/src/analytics.ts`: `byUA` を `uaSplit`（human / bot の総数と、それぞれの上位 N 件の内訳）へ置き換えた。総数を内訳の合計から出していないのは、内訳が上位 10 件で切られており種類が多いほど実際より小さく見えるため。
- `site/src/views/dashboard.tsx`: 「人間の訪問とロボットの巡回（全期間の累計）」ブロックを追加。カード 2 枚（人間 / ロボット）と表 2 つ（人間: クライアント種別 / ロボット: 種類別）、および遡及不可の注記。
- `site/tools/seed-local.mjs` / `site/README.md` / `site/tools/README.md` を新しい値域に合わせて更新。

## AC#5: /features を計測対象に含めるか → 含めない（現状維持）

理由は 3 点。

1. **events がページを区別する列を持たない**（`site/src/schema.ts`）。計上すると `visit` に別ページの訪問が混ざり、LP からの新規獲得を測る指標の意味が壊れる。ページ列を足すのは本タスクの範囲外（ADR 0004 は「新しい列・テーブル・計測経路は追加しない」を前提に決定している）。
2. **計測しても数が信用できない。** /features は `Cache-Control: public, max-age=3600` を返す（`site/src/routes/public.tsx:29`）。CDN/ブラウザキャッシュにヒットしたリクエストは Worker に届かないため、系統的に過少計上される。正しく数えるにはキャッシュを外すことになり、計測のために配信特性を悪くする取引になる。
3. **クローラの到来量は / で足りる。** ボット計測の目的は AI クローラの到来量の実測（llms.txt の要否判断、ADR 0004）であり、サイトを巡回するクローラは sitemap の先頭にある / を必ず踏む。/features を足しても「どのページを見たか」は分からない（1 の列が無いため）ので、判断材料は増えない。

再検討するのは、events にページを区別する列を入れると決めたときか、/features 単独の流入を測る要件が生まれたとき。

## 検証

- `npx vitest run`: 8 files / 130 tests すべて成功（追加分を含む）
- `npm run typecheck`: エラーなし
- `npx markdownlint-cli2`: 67 files / 0 issues
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
summarizeUA に UA トークンによるボット判定を追加し（ADR 0004）、ダッシュボードで人間の訪問とロボットの巡回を分離した。既知の検索クローラ・AI クローラは 'bot:GPTBot' のように種類別の値を返し、未知のボットは 'bot:other' へ落ちる。ボット値は 'bot:' 接頭辞で識別するため、集計側は名前を列挙せず LIKE 'bot:%' だけで分離でき、トークンを増やしても同期漏れが起きない。ボット判定はブラウザ判定より先に置いた（Googlebot の UA は Chrome/ を含むため）。過去データを遡って分類できないことはダッシュボードの注記に出した。/features は計測対象に含めない判断とその理由を Notes に記録した。検証は vitest 130 件成功・tsc エラーなし・markdownlint 0 issues。
<!-- SECTION:FINAL_SUMMARY:END -->
