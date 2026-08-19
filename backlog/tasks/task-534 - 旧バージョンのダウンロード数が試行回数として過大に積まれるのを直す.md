---
id: TASK-534
title: 旧バージョンのダウンロード数が試行回数として過大に積まれるのを直す
status: To Do
assignee: []
created_date: '2026-08-19 14:53'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 772000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-533 の調査中に判明した別件。/releases/:tag/:file の archive 計上が、ダウンロードの成否と無関係に積まれる。

- recordEvent が R2 の取得判定より前にある（site/src/routes/public.tsx:138-147）。DIST.get が null で GitHub へ 302 する失敗系でも 1 件残るため、数えているのは「ダウンロード」ではなく「リンクを叩いた回数」。
- R2 ヒット時は immutable 付き 200 でブラウザキャッシュが効く（site/src/routes/public.tsx:182-194）が、R2 に実体の無い旧タグは毎回 302 で毎回 Worker を通るため、同一利用者の再クリックやリトライがそのまま加算される。
- Hono の get は HEAD も拾うため、HEAD・レンジ要求・ダウンロードマネージャの再接続もそれぞれ 1 件になる。
- ボット除去は記録時ではなく集計時の HUMAN_ONLY（UA 接頭辞 + as_org、site/src/analytics.ts:398-449）のみ。/releases は robots.txt で許可されており（site/src/routes/public.tsx:206-212）、表は 1 リリース = 1 リンク（site/src/views/releases.tsx:26-28, 133）なので、UA が普通のブラウザに見えるクローラが全行を辿ると行数ぶんまとめて計上される。

同じ性質が lp / sparkle 側にどこまであるかは未確認。着手時に 3 経路を並べて、どこまで揃えるかを先に決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 archive の計上が、配信に成功した要求だけを数えるようになっている（302 フォールバックの扱いを決めた上で実装する）
- [ ] #2 HEAD 要求とレンジ要求の再接続が重複計上されない
- [ ] #3 lp / sparkle 経路との計上条件の差を調べ、揃える／揃えないの判断を Implementation Notes に残す
- [ ] #4 既存データは遡って直さない方針でよいか判断し、その結論を記録する
<!-- AC:END -->
