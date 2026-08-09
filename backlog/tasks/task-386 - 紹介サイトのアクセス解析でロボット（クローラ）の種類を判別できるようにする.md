---
id: TASK-386
title: 紹介サイトのアクセス解析でロボット（クローラ）の種類を判別できるようにする
status: To Do
assignee: []
created_date: '2026-08-09 08:28'
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
- [ ] #1 summarizeUA が主要な検索クローラ（Googlebot / bingbot 等）と AI クローラ（GPTBot / ClaudeBot / OAI-SearchBot / PerplexityBot 等）を個別の値として返す
- [ ] #2 判別できないボットは 'other' に埋もれず、ボットと分かる値（bot-other 等）に分類される
- [ ] #3 上記の分類がユニットテストで ON/OFF 両方向（既知ボットの UA / 通常ブラウザの UA）について担保されている
- [ ] #4 ダッシュボードで人間の訪問とロボットの巡回が分離して表示され、ロボットは種類別の内訳が見える
- [ ] #5 /features を計測対象に含めるかを判断し、その結論と理由を Implementation Notes に記録する
- [ ] #6 過去データを遡って分類できないこと（適用日以降のみ内訳が出ること）がダッシュボードの表示または注記から読み取れる
<!-- AC:END -->
