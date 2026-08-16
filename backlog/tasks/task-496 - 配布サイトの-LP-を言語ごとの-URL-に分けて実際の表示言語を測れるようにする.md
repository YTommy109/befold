---
id: TASK-496
title: 配布サイトの LP を言語ごとの URL に分けて実際の表示言語を測れるようにする
status: To Do
assignee: []
created_date: '2026-08-16 03:48'
labels: []
dependencies: []
priority: medium
ordinal: 733000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488.1 の設計レビューで切り出した論点。計測の副産物として決めるべきでない、LP 多言語化そのものの設計判断なので独立させる。

現状、LP と /features は日英の本文を同じ HTML に持ち、`[lang]` 属性 + `hidden` の付け外しで出し分けている（`site/src/views/shared.tsx` の `LANG_SCRIPT`）。表示言語は `localStorage` の `befold-lang` だけで決まり、**未設定なら常に日本語**（`saved && saved !== 'ja'` のときだけ切り替える）。

このためサーバ側からは実際の表示言語が観測できない。TASK-488.1 で記録した `events.browser_lang` は Accept-Language 由来の**ブラウザ言語設定**であり、「英語を求めて来た人の数」は測れるが「英語で読んだ人の数」は測れない（初回訪問の en ユーザーは日本語を読んでいる）。

言語ごとに URL を分ける（`/en` など）と表示言語が確実に測れ、SEO 上も正しくなる（現状は同一 URL に 2 言語が同居し、hreflang も出せない）。一方で canonical / og:url / sitemap.xml / robots.txt / JSON-LD / 旧ホストからの 301（ADR 0007）へ全面的に波及し、既存テストの広い範囲（`site/test/public.test.ts`）を書き換えることになる。

着手前に、言語の決め方（Accept-Language による自動リダイレクト有無、localStorage との優先順位、切替 UI の遷移先）を決めること。自動リダイレクトは検索エンジンのクロールを壊しやすいので、採否とその理由を残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LP と /features が言語ごとの URL で配信され、同一 URL に 2 言語が同居しない
- [ ] #2 canonical / og:url / hreflang / sitemap.xml / JSON-LD が言語ごとの URL と整合している
- [ ] #3 言語切替 UI が対応する言語の URL へ遷移し、localStorage との関係が決まっている
- [ ] #4 events から実際の表示言語が読める（page または新しい列で言語ごとの URL が区別できる）
- [ ] #5 Accept-Language による自動リダイレクトの採否とその理由が Implementation Notes に記録されている
- [ ] #6 site の vitest と typecheck が通る
<!-- AC:END -->
